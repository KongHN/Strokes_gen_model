import os
import random
from PIL import Image, ImageFilter
import numpy as np


def load_strokes(folder_path):
    """加载指定文件夹中的所有PNG笔画图片，并提高其像素"""
    strokes = []
    for filename in os.listdir(folder_path):
        if filename.lower().endswith('.png'):
            try:
                filepath = os.path.join(folder_path, filename)
                stroke = Image.open(filepath).convert('RGBA')
                # 先提高笔画图片的像素
                stroke = enhance_resolution(stroke)
                # 再增强白色区域
                stroke = enhance_white(stroke)
                strokes.append(stroke)
            except Exception as e:
                print(f"无法加载图片 {filename}: {e}")
    return strokes


def enhance_resolution(image, scale_factor=9):
    """提高图像分辨率（像素），使用Lanczos滤镜进行超采样"""
    # 计算新尺寸（按比例放大）
    new_width = int(image.size[0] * scale_factor)
    new_height = int(image.size[1] * scale_factor)

    # 使用高质量的Lanczos滤镜放大图像，提升像素细节
    high_res_image = image.resize((new_width, new_height), Image.LANCZOS)

    # 可选：轻微锐化处理，增强放大后的清晰度
    high_res_image = high_res_image.filter(ImageFilter.UnsharpMask(radius=1, percent=100, threshold=2))

    return high_res_image


def enhance_white(image):
    """增强图像中的白色区域，使其更加明显"""
    width, height = image.size
    pixels = image.load()

    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            if a > 0:
                brightness = (r + g + b) / 3
                if brightness > 180:
                    pixels[x, y] = (255, 255, 255, a)
                elif brightness < 75:
                    pixels[x, y] = (0, 0, 0, a)
    return image


def resize_stroke(stroke, target_area, canvas_size):
    """调整笔画大小，确保不超过画布的0.95尺寸（避免过大）"""
    width, height = stroke.size
    current_area = width * height
    if current_area == 0:
        return stroke  # 避免除以零

    scale_factor = (target_area / current_area) ** 0.5

    # 限制最大尺寸为画布的0.95
    max_width = int(canvas_size[0] * 0.95)
    max_height = int(canvas_size[1] * 0.95)

    new_width = min(int(width * scale_factor), max_width)
    new_height = min(int(height * scale_factor), max_height)

    # 确保最小尺寸
    new_width = max(new_width, 10)
    new_height = max(new_height, 10)

    return stroke.resize((new_width, new_height), Image.LANCZOS)


def place_stroke_with_attraction(canvas, stroke, center_attraction=0.85, max_attempts=500):
    """尝试在画布上放置笔画，带有向中心吸引的趋势"""
    canvas_width, canvas_height = canvas.size
    stroke_width, stroke_height = stroke.size

    # 检查笔画是否过大
    if stroke_width >= canvas_width or stroke_height >= canvas_height:
        return canvas, None

    center_x, center_y = canvas_width // 2, canvas_height // 2

    for attempt in range(max_attempts):
        # 扩大基础位置范围
        base_x_min = 0
        base_x_max = canvas_width - stroke_width
        base_y_min = 0
        base_y_max = canvas_height - stroke_height

        # 确保范围有效
        if base_x_min > base_x_max or base_y_min > base_y_max:
            continue  # 跳过无效范围

        base_x = random.randint(base_x_min, base_x_max)
        base_y = random.randint(base_y_min, base_y_max)

        # 计算吸引力
        dist_x = center_x - (base_x + stroke_width // 2)
        dist_y = center_y - (base_y + stroke_height // 2)
        attraction_factor = min(1.0, attempt / max_attempts * center_attraction)
        attracted_x = int(base_x + dist_x * attraction_factor)
        attracted_y = int(base_y + dist_y * attraction_factor)

        # 确保位置在画布内
        x = max(0, min(attracted_x, canvas_width - stroke_width))
        y = max(0, min(attracted_y, canvas_height - stroke_height))
        position = (x, y)

        if not is_overlapping(canvas, stroke, position, threshold=0.75):
            stroke_layer = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
            stroke_layer.paste(stroke, position, stroke)
            canvas = Image.alpha_composite(canvas, stroke_layer)
            return canvas, position

    return canvas, None


def is_overlapping(canvas, stroke, position, threshold=0.5):
    """检查笔画放置在指定位置是否与现有内容重叠超过阈值"""
    x, y = position
    width, height = stroke.size

    try:
        canvas_region = canvas.crop((x, y, x + width, y + height))
    except ValueError:
        return True

    stroke_array = np.array(stroke)
    canvas_array = np.array(canvas_region)

    stroke_alpha = stroke_array[:, :, 3] > 0
    if canvas_array.size == 0:
        return False

    canvas_non_black = np.sum(canvas_array[:, :, :3], axis=2) > 0
    overlap = np.logical_and(stroke_alpha, canvas_non_black)
    overlap_ratio = np.sum(overlap) / np.sum(stroke_alpha) if np.sum(stroke_alpha) > 0 else 0

    return overlap_ratio > threshold


def group_strokes_by_type(strokes):
    """根据笔画类型进行分组"""
    horizontal = []
    vertical = []
    others = []

    for stroke in strokes:
        width, height = stroke.size
        if width > height * 1.5:
            horizontal.append(stroke)
        elif height > width * 1.5:
            vertical.append(stroke)
        else:
            others.append(stroke)

    return horizontal, vertical, others


def get_bmp_size(folder_path):
    """获取文件夹中bmp图片的尺寸"""
    for filename in os.listdir(folder_path):
        if filename.lower().endswith('.bmp'):
            try:
                filepath = os.path.join(folder_path, filename)
                with Image.open(filepath) as img:
                    return img.size
            except Exception as e:
                print(f"读取bmp图片 {filename} 尺寸时出错: {e}")
    return (200, 200)  # 默认尺寸


def assemble_character(strokes, output_path, canvas_size):
    """将多个笔画组合成一个类似汉字的符号"""
    canvas = Image.new('RGBA', canvas_size, (0, 0, 0, 255))
    total_area = canvas_size[0] * canvas_size[1]
    target_area_per_stroke = total_area / (len(strokes) * 0.3)  # 增大单个笔画面积

    random.shuffle(strokes)
    horizontal, vertical, others = group_strokes_by_type(strokes)

    structured_strokes = []
    stroke_types = [horizontal, vertical, others]
    while any(stroke_types):
        non_empty_types = [t for t in stroke_types if t]
        if not non_empty_types:
            break
        selected_type = random.choice(non_empty_types)
        structured_strokes.append(selected_type.pop(0))

    for stroke in structured_strokes:
        resized_stroke = resize_stroke(stroke, target_area_per_stroke, canvas_size)
        canvas, position = place_stroke_with_attraction(
            canvas, resized_stroke,
            center_attraction=0.80
        )

    # 检查是否有非透明像素
    alpha_channel = np.array(canvas)[:, :, 3]
    if np.sum(alpha_channel > 0) == 0 and strokes:
        resized_stroke = resize_stroke(strokes[0], target_area_per_stroke, canvas_size)
        x = (canvas_size[0] - resized_stroke.size[0]) // 2
        y = (canvas_size[1] - resized_stroke.size[1]) // 2
        stroke_layer = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
        stroke_layer.paste(resized_stroke, (x, y), resized_stroke)
        canvas = Image.alpha_composite(canvas, stroke_layer)

    canvas_rgb = canvas.convert('RGB')
    canvas_rgb.save(output_path)
    print(f"已生成合成图片: {output_path}")
    return output_path


if __name__ == "__main__":
    INPUT_FOLDER = r"F:\科研\06Machine Learning, EEG, and Word Reading in Children\Strokes_PNG"
    OUTPUT_FOLDER = r"F:\科研\06Machine Learning, EEG, and Word Reading in Children\output"
    RANDOM_SEED = None

    if RANDOM_SEED is not None:
        random.seed(RANDOM_SEED)

    for subfolder in os.listdir(INPUT_FOLDER):
        subfolder_path = os.path.join(INPUT_FOLDER, subfolder)
        if os.path.isdir(subfolder_path):
            canvas_size = get_bmp_size(subfolder_path)
            print(f"子文件夹 {subfolder} 的画布尺寸: {canvas_size}")

            strokes = load_strokes(subfolder_path)
            if not strokes:
                print(f"错误: 在 {subfolder_path} 中未找到PNG格式的笔画图片")
            else:
                print(f"已加载 {len(strokes)} 个笔画图片，来自 {subfolder_path}")
                output_path = os.path.join(OUTPUT_FOLDER, f"{subfolder}.bmp")
                assemble_character(strokes, output_path, canvas_size)