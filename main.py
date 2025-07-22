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
                pass  # 忽略错误
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


def place_stroke(canvas, stroke, position):
    """在指定位置放置笔画"""
    stroke_layer = Image.new('RGBA', canvas.size, (0, 0, 0, 0))
    stroke_layer.paste(stroke, position, stroke)
    return Image.alpha_composite(canvas, stroke_layer)


def is_overlapping(canvas, stroke, position, threshold=0.05):
    """检查笔画放置在指定位置是否与现有内容重叠超过阈值
    允许交叉但不允许实质性重叠（像素级重合）
    """
    x, y = position
    stroke_w, stroke_h = stroke.size
    canvas_w, canvas_h = canvas.size

    # 检查是否完全超出画布范围
    if x + stroke_w < 0 or x > canvas_w or y + stroke_h < 0 or y > canvas_h:
        return True  # 完全超出范围视为无效

    # 计算实际重叠区域
    crop_x1 = max(0, x)
    crop_y1 = max(0, y)
    crop_x2 = min(canvas_w, x + stroke_w)
    crop_y2 = min(canvas_h, y + stroke_h)

    # 无实际重叠区域
    if crop_x1 >= crop_x2 or crop_y1 >= crop_y2:
        return False

    # 提取重叠区域
    try:
        canvas_region = canvas.crop((crop_x1, crop_y1, crop_x2, crop_y2))
        stroke_region = stroke.crop((
            crop_x1 - x, crop_y1 - y,
            crop_x2 - x, crop_y2 - y
        ))
    except ValueError:
        return True  # 处理裁剪错误

    # 转换为数组进行重叠检测
    stroke_array = np.array(stroke_region)
    canvas_array = np.array(canvas_region)

    # 提取笔画的非透明区域（实际笔画部分）
    stroke_alpha = stroke_array[:, :, 3] > 10  # 忽略几乎透明的部分
    total_stroke_area = np.sum(stroke_alpha)

    if total_stroke_area == 0:
        return False  # 空笔画不重叠

    # 提取画布上的已有笔画区域
    canvas_alpha = canvas_array[:, :, 3] > 10  # 忽略几乎透明的部分

    # 计算重叠比例（像素级重合）
    overlap = np.logical_and(stroke_alpha, canvas_alpha)
    overlap_ratio = np.sum(overlap) / total_stroke_area

    return overlap_ratio > threshold


def get_bmp_size(folder_path):
    """获取文件夹中bmp图片的尺寸作为画布尺寸"""
    for filename in os.listdir(folder_path):
        if filename.lower().endswith('.bmp'):
            try:
                with Image.open(os.path.join(folder_path, filename)) as img:
                    return img.size
            except Exception:
                pass  # 忽略错误
    return (256, 256)  # 默认画布尺寸


def calculate_coverage(canvas):
    """计算画布被笔画覆盖的比例"""
    canvas_array = np.array(canvas)
    canvas_alpha = canvas_array[:, :, 3] > 10
    return np.sum(canvas_alpha) / (canvas.size[0] * canvas.size[1])


def get_character_regions(canvas_size):
    """定义汉字可能的笔画分布区域"""
    w, h = canvas_size

    # 定义主要结构区域（基于汉字的九宫格结构）
    return [
        (0, 0, w // 3, h // 3),  # 左上
        (w // 3, 0, 2 * w // 3, h // 3),  # 中上
        (2 * w // 3, 0, w, h // 3),  # 右上
        (0, h // 3, w // 3, 2 * h // 3),  # 左中
        (w // 3, h // 3, 2 * w // 3, 2 * h // 3),  # 中心
        (2 * w // 3, h // 3, w, 2 * h // 3),  # 右中
        (0, 2 * h // 3, w // 3, h),  # 左下
        (w // 3, 2 * h // 3, 2 * w // 3, h),  # 中下
        (2 * w // 3, 2 * h // 3, w, h)  # 右下
    ]


def find_optimal_position(canvas, stroke, regions, max_attempts=50):
    """在指定区域内寻找最优放置位置"""
    canvas_w, canvas_h = canvas.size
    stroke_w, stroke_h = stroke.size

    # 随机打乱区域顺序，增加多样性
    random.shuffle(regions)

    for region in regions:
        rx1, ry1, rx2, ry2 = region

        # 计算区域内可放置的空间
        region_w = rx2 - rx1
        region_h = ry2 - ry1

        if region_w < stroke_w or region_h < stroke_h:
            continue  # 区域太小，无法放置

        for _ in range(max_attempts):
            # 在区域内随机选择位置
            x = rx1 + random.randint(0, region_w - stroke_w)
            y = ry1 + random.randint(0, region_h - stroke_h)

            # 检查重叠
            if not is_overlapping(canvas, stroke, (x, y)):
                return (x, y)

    # 如果区域内找不到合适位置，尝试整个画布
    for _ in range(max_attempts):
        x = random.randint(0, max(0, canvas_w - stroke_w))
        y = random.randint(0, max(0, canvas_h - stroke_h))

        if not is_overlapping(canvas, stroke, (x, y)):
            return (x, y)

    return None  # 无法找到合适位置


def calculate_stroke_importance(stroke, canvas_size):
    """计算笔画对汉字结构的重要性（基于大小和方向）"""
    stroke_w, stroke_h = stroke.size
    canvas_w, canvas_h = canvas_size

    # 计算笔画占画布的比例
    area_ratio = (stroke_w * stroke_h) / (canvas_w * canvas_h)

    # 计算笔画的纵横比（用于判断是否为横/竖笔画）
    aspect_ratio = max(stroke_w, stroke_h) / min(stroke_w, stroke_h) if min(stroke_w, stroke_h) > 0 else 1

    # 水平或垂直笔画对汉字结构更重要
    is_horizontal = stroke_w > stroke_h * 1.5
    is_vertical = stroke_h > stroke_w * 1.5

    # 重要性评分
    importance = area_ratio * (1.5 if is_horizontal or is_vertical else 1.0)

    return importance


def assemble_character(strokes, output_path, canvas_size):
    """组合所有笔画，生成更像汉字的符号"""
    canvas = Image.new('RGBA', canvas_size, (0, 0, 0, 0))  # 透明背景
    canvas_w, canvas_h = canvas_size
    total_strokes = len(strokes)

    if total_strokes == 0:
        print("没有找到笔画图片")
        return

    # 按重要性排序笔画（大笔画和横/竖笔画优先）
    strokes.sort(key=lambda s: calculate_stroke_importance(s, canvas_size), reverse=True)

    # 获取汉字区域划分
    regions = get_character_regions(canvas_size)

    # 记录每个区域的笔画数量，用于平衡分布
    region_counts = [0] * len(regions)

    # 先放置几个关键笔画，构建基本结构
    if total_strokes >= 1:
        # 第一个笔画：通常是主横或主竖
        position = find_optimal_position(canvas, strokes[0], [regions[4]])  # 优先放在中心区域
        if position:
            canvas = place_stroke(canvas, strokes[0], position)
            print(f"放置笔画 1/{total_strokes} (中心区域)")

    if total_strokes >= 2:
        # 第二个笔画：通常是主竖或主横，与第一个笔画交叉
        position = find_optimal_position(canvas, strokes[1], [regions[4]])  # 优先放在中心区域
        if position:
            canvas = place_stroke(canvas, strokes[1], position)
            print(f"放置笔画 2/{total_strokes} (中心区域)")

    # 放置剩余笔画，优先填充空白区域
    for i in range(2, total_strokes):
        # 计算每个区域的"权重"，优先选择笔画少的区域
        weights = [1.0 / (count + 1) for count in region_counts]
        normalized_weights = [w / sum(weights) for w in weights]

        # 根据权重选择区域
        selected_regions = random.choices(
            regions,
            weights=normalized_weights,
            k=min(3, len(regions))  # 尝试3个区域
        )

        position = find_optimal_position(canvas, strokes[i], selected_regions)

        if position:
            canvas = place_stroke(canvas, strokes[i], position)

            # 记录该区域的笔画数量增加
            for idx, region in enumerate(regions):
                rx1, ry1, rx2, ry2 = region
                x, y = position
                if rx1 <= x <= rx2 and ry1 <= y <= ry2:
                    region_counts[idx] += 1
                    break

            print(f"放置笔画 {i + 1}/{total_strokes} (区域: {regions.index(selected_regions[0]) + 1})")

    # 添加黑色背景
    background = Image.new('RGBA', canvas_size, (0, 0, 0, 255))
    canvas = Image.alpha_composite(background, canvas)

    # 保存结果
    canvas_rgb = canvas.convert('RGB')
    canvas_rgb.save(output_path)

    coverage = calculate_coverage(canvas)
    print(f"已生成合成图片: {output_path}")
    print(f"总笔画数: {total_strokes}, 覆盖率: {coverage:.2f}")


if __name__ == "__main__":
    INPUT_FOLDER = r"C:\Users\孔昊男\Desktop\Strokes_PNG"
    OUTPUT_FOLDER = r"C:\Users\孔昊男\Desktop\output"
    RANDOM_SEED = 42  # 固定随机种子，便于调试

    if RANDOM_SEED is not None:
        random.seed(RANDOM_SEED)

    # 确保输出文件夹存在
    os.makedirs(OUTPUT_FOLDER, exist_ok=True)

    # 处理每个子文件夹
    for subfolder in os.listdir(INPUT_FOLDER):
        subfolder_path = os.path.join(INPUT_FOLDER, subfolder)
        if os.path.isdir(subfolder_path):
            print(f"\n处理文件夹: {subfolder}")
            canvas_size = get_bmp_size(subfolder_path)
            strokes = load_strokes(subfolder_path)

            if strokes:
                output_path = os.path.join(OUTPUT_FOLDER, f"{subfolder}.bmp")
                assemble_character(strokes, output_path, canvas_size)
            else:
                print(f"文件夹 {subfolder} 中未找到PNG笔画图片")