import os
import random
from PIL import Image
import numpy as np


def load_strokes(folder_path):
    """加载指定文件夹中的所有PNG笔画图片"""
    strokes = []
    for filename in os.listdir(folder_path):
        if filename.lower().endswith('.png'):
            try:
                filepath = os.path.join(folder_path, filename)
                stroke = Image.open(filepath).convert('RGBA')
                stroke = enhance_white(stroke)
                strokes.append(stroke)
            except Exception:
                pass  # 移除错误提示
    return strokes


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


def resize_to_fill_multiple(stroke, canvas_size, boundaries):
    """将笔画缩放至充满多个边界方向的画布"""
    canvas_w, canvas_h = canvas_size
    stroke_w, stroke_h = stroke.size

    # 根据需要触碰的边界计算缩放比例
    scale_x = canvas_w / max(stroke_w, 1)
    scale_y = canvas_h / max(stroke_h, 1)

    # 如果需要触碰两个边界，选择合适的缩放比例
    if len(boundaries) >= 2:
        if ('left' in boundaries or 'right' in boundaries) and ('top' in boundaries or 'bottom' in boundaries):
            # 需要同时触碰水平和垂直边界
            scale = max(scale_x, scale_y)
        else:
            # 只需要触碰两个水平或垂直边界
            scale = min(scale_x, scale_y)
    else:
        scale = max(scale_x, scale_y)

    # 计算新尺寸
    new_w = int(stroke_w * scale)
    new_h = int(stroke_h * scale)

    return stroke.resize((new_w, new_h), Image.LANCZOS)


def place_stroke(canvas, stroke, position):
    """在指定位置放置笔画"""
    stroke_layer = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    stroke_layer.paste(stroke, position, stroke)
    return Image.alpha_composite(canvas, stroke_layer)


def is_overlapping(canvas, stroke, position, threshold=0.1):
    """检查笔画放置在指定位置是否与现有内容重叠超过阈值"""
    x, y = position
    width, height = stroke.size

    try:
        canvas_region = canvas.crop((x, y, x + width, y + height))
    except ValueError:
        return True  # 超出范围视为重叠

    stroke_array = np.array(stroke)
    canvas_array = np.array(canvas_region)

    # 提取笔画的非透明区域
    stroke_alpha = stroke_array[:, :, 3] > 0
    total_stroke_area = np.sum(stroke_alpha)

    if total_stroke_area == 0:
        return False  # 空笔画不重叠

    # 提取画布的非黑色区域（已有笔画）
    canvas_non_black = np.sum(canvas_array[:, :, :3], axis=2) > 10  # 允许轻微黑色
    overlap = np.logical_and(stroke_alpha, canvas_non_black)
    overlap_ratio = np.sum(overlap) / total_stroke_area

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
                with Image.open(os.path.join(folder_path, filename)) as img:
                    return img.size
            except Exception:
                pass  # 移除错误提示
    return (200, 200)  # 默认尺寸


def place_main_stroke(canvas, stroke, canvas_size, boundaries, max_attempts=50):
    """强制将主要笔画放置在指定边界，确保至少触碰两个边界，减少重叠"""
    canvas_w, canvas_h = canvas_size

    for attempt in range(max_attempts):
        # 缩放笔画至合适大小
        filled_stroke = resize_to_fill_multiple(stroke, canvas_size, boundaries)
        stroke_w, stroke_h = filled_stroke.size

        # 根据需要触碰的边界确定位置
        x, y = 0, 0

        # 确保触碰指定的边界
        if 'left' in boundaries:
            x = 0
        elif 'right' in boundaries:
            x = canvas_w - stroke_w

        if 'top' in boundaries:
            y = 0
        elif 'bottom' in boundaries:
            y = canvas_h - stroke_h

        # 对于只需要触碰两个水平或垂直边界的情况，随机调整另一个坐标
        if ('left' in boundaries and 'right' in boundaries) and not ('top' in boundaries or 'bottom' in boundaries):
            y = random.randint(0, max(0, canvas_h - stroke_h))
        elif ('top' in boundaries and 'bottom' in boundaries) and not ('left' in boundaries or 'right' in boundaries):
            x = random.randint(0, max(0, canvas_w - stroke_w))

        # 微调位置以减少重叠
        if attempt > 0:  # 首次尝试使用原始位置，后续尝试微调
            if 'left' not in boundaries and 'right' not in boundaries:
                x = random.randint(max(0, x - 20), min(canvas_w - stroke_w, x + 20))
            if 'top' not in boundaries and 'bottom' not in boundaries:
                y = random.randint(max(0, y - 20), min(canvas_h - stroke_h, y + 20))

        # 最终位置检查（确保有效）
        x = max(0, min(x, canvas_w - stroke_w))
        y = max(0, min(y, canvas_h - stroke_h))

        # 检查重叠
        if not is_overlapping(canvas, filled_stroke, (x, y)):
            return place_stroke(canvas, filled_stroke, (x, y)), filled_stroke

    # 多次尝试失败后强制放置
    filled_stroke = resize_to_fill_multiple(stroke, canvas_size, boundaries)
    stroke_w, stroke_h = filled_stroke.size

    # 确保触碰边界
    if 'left' in boundaries:
        x = 0
    elif 'right' in boundaries:
        x = canvas_w - stroke_w

    if 'top' in boundaries:
        y = 0
    elif 'bottom' in boundaries:
        y = canvas_h - stroke_h

    return place_stroke(canvas, filled_stroke, (x, y)), filled_stroke


def place_secondary_stroke(canvas, stroke, canvas_size, max_attempts=100):
    """放置次要笔画，确保触碰一个边界且尽量减少重叠"""
    canvas_w, canvas_h = canvas_size

    # 随机选择一个边界
    boundaries = ['left', 'right', 'top', 'bottom']
    boundary = random.choice(boundaries)

    for attempt in range(max_attempts):
        # 缩放笔画以触碰边界
        scaled_stroke = resize_to_fill(stroke, canvas_size, boundary)
        stroke_w, stroke_h = scaled_stroke.size

        # 根据边界确定位置
        if boundary == 'left':
            x = 0
            y = random.randint(0, max(0, canvas_h - stroke_h))
        elif boundary == 'right':
            x = canvas_w - stroke_w
            y = random.randint(0, max(0, canvas_h - stroke_h))
        elif boundary == 'top':
            y = 0
            x = random.randint(0, max(0, canvas_w - stroke_w))
        else:  # bottom
            y = canvas_h - stroke_h
            x = random.randint(0, max(0, canvas_w - stroke_w))

        # 微调位置以减少重叠
        if attempt > 0:
            # 水平微调（确保范围有效）
            if boundary not in ['left', 'right']:
                min_x = max(0, x - 30)
                max_x = min(canvas_w - stroke_w, x + 30)
                if min_x <= max_x:
                    x = random.randint(min_x, max_x)

            # 垂直微调（确保范围有效）
            if boundary not in ['top', 'bottom']:
                min_y = max(0, y - 30)
                max_y = min(canvas_h - stroke_h, y + 30)
                if min_y <= max_y:
                    y = random.randint(min_y, max_y)

        # 检查重叠
        if not is_overlapping(canvas, scaled_stroke, (x, y)):
            return place_stroke(canvas, scaled_stroke, (x, y)), scaled_stroke

    # 多次尝试失败后强制放置
    scaled_stroke = resize_to_fill(stroke, canvas_size, boundary)
    stroke_w, stroke_h = scaled_stroke.size

    if boundary == 'left':
        x = 0
        y = random.randint(0, max(0, canvas_h - stroke_h))
    elif boundary == 'right':
        x = canvas_w - stroke_w
        y = random.randint(0, max(0, canvas_h - stroke_h))
    elif boundary == 'top':
        y = 0
        x = random.randint(0, max(0, canvas_w - stroke_w))
    else:  # bottom
        y = canvas_h - stroke_h
        x = random.randint(0, max(0, canvas_w - stroke_w))

    return place_stroke(canvas, scaled_stroke, (x, y)), scaled_stroke


def resize_to_fill(stroke, canvas_size, boundary):
    """将笔画缩放至充满对应边界方向的画布（确保触碰边界）"""
    canvas_w, canvas_h = canvas_size
    stroke_w, stroke_h = stroke.size

    # 计算基础缩放比例
    if boundary in ['left', 'right']:
        # 水平边界：宽度充满画布
        scale = canvas_w / max(stroke_w, 1)  # 避免除零
    else:  # top, bottom
        # 垂直边界：高度充满画布
        scale = canvas_h / max(stroke_h, 1)

    # 计算新尺寸
    new_w = int(stroke_w * scale)
    new_h = int(stroke_h * scale)

    # 强制充满对应方向（确保100%触碰）
    if boundary in ['left', 'right']:
        new_w = canvas_w  # 宽度=画布宽度，必然触碰左右边界
    else:
        new_h = canvas_h  # 高度=画布高度，必然触碰上下边界

    return stroke.resize((new_w, new_h), Image.LANCZOS)


def assemble_character(strokes, output_path, canvas_size):
    """组合所有笔画：先放置四个触碰两个边界的笔画，再随机放置剩余笔画"""
    canvas = Image.new('RGBA', canvas_size, (0, 0, 0, 255))  # 黑色背景
    canvas_w, canvas_h = canvas_size
    total_strokes = len(strokes)
    if total_strokes == 0:
        return

    # 边界组合列表（每个组合包含两个边界）
    main_boundary_combinations = [
        ['left', 'top'],  # 左上
        ['right', 'top'],  # 右上
        ['left', 'bottom'],  # 左下
        ['right', 'bottom'],  # 右下
    ]

    # 按大小排序笔画，先放置大笔画
    strokes_sorted = sorted(strokes, key=lambda s: s.size[0] * s.size[1], reverse=True)

    # 1. 放置四个主要笔画（触碰两个边界）
    main_strokes = strokes_sorted[:4]
    remaining_strokes = strokes_sorted[4:]

    for i, stroke in enumerate(main_strokes):
        if i < len(main_boundary_combinations):
            boundaries = main_boundary_combinations[i]
            canvas, _ = place_main_stroke(canvas, stroke, canvas_size, boundaries)

    # 2. 放置剩余笔画（触碰一个边界）
    for stroke in remaining_strokes:
        canvas, _ = place_secondary_stroke(canvas, stroke, canvas_size)

    # 保存结果
    canvas_rgb = canvas.convert('RGB')
    canvas_rgb.save(output_path)
    # 只保留目标打印信息
    print(f"已生成合成图片（使用全部{total_strokes}个笔画）: {output_path}")


if __name__ == "__main__":
    INPUT_FOLDER = r"C:\Users\孔昊男\Desktop\Strokes_PNG"
    OUTPUT_FOLDER = r"C:\Users\孔昊男\Desktop\output"
    RANDOM_SEED = None

    if RANDOM_SEED is not None:
        random.seed(RANDOM_SEED)
    os.makedirs(OUTPUT_FOLDER, exist_ok=True)  # 确保输出文件夹存在

    for subfolder in os.listdir(INPUT_FOLDER):
        subfolder_path = os.path.join(INPUT_FOLDER, subfolder)
        if os.path.isdir(subfolder_path):
            canvas_size = get_bmp_size(subfolder_path)
            strokes = load_strokes(subfolder_path)
            if strokes:
                output_path = os.path.join(OUTPUT_FOLDER, f"{subfolder}.bmp")
                assemble_character(strokes, output_path, canvas_size)