function [] = chinese_character_generator()
    % 配置参数
    INPUT_FOLDER = 'C:\Users\孔昊男\Desktop\Strokes_PNG';
    OUTPUT_FOLDER = 'C:\Users\孔昊男\Desktop\output';
    RANDOM_SEED = 42;  % 固定随机种子，便于调试
    
    % 设置随机种子
    if ~isempty(RANDOM_SEED)
        rng(RANDOM_SEED);
    end
    
    % 确保输出文件夹存在
    if ~exist(OUTPUT_FOLDER, 'dir')
        mkdir(OUTPUT_FOLDER);
    end
    
    % 获取所有子文件夹
    subfolders = dir(INPUT_FOLDER);
    subfolders = subfolders([subfolders.isdir]);
    subfolders = subfolders(~ismember({subfolders.name}, {'.', '..'}));
    
    % 处理每个子文件夹
    for i = 1:length(subfolders)
        subfolder = subfolders(i).name;
        subfolder_path = fullfile(INPUT_FOLDER, subfolder);
        fprintf('\n处理文件夹: %s\n', subfolder);
        
        % 获取画布尺寸
        canvas_size = get_bmp_size(subfolder_path);
        
        % 仅使用Java ImageIO方法加载笔画图片
        strokes = load_strokes_imageio(subfolder_path, true, 180, 75);
        
        if ~isempty(strokes)
            output_path = fullfile(OUTPUT_FOLDER, [subfolder '.bmp']);
            assemble_character(strokes, output_path, canvas_size);
        else
            fprintf('文件夹 %s 中未找到有效PNG笔画图片\n', subfolder);
        end
    end
end

function strokes = load_strokes_imageio(folder_path, enhance_enable, bright_white_thresh, dark_black_thresh)
    % 仅使用Java ImageIO方法加载PNG笔画图片
    strokes = {};
    files = dir(fullfile(folder_path, '*.png'));
    
    for i = 1:length(files)
        filepath = fullfile(folder_path, files(i).name);
        fprintf('尝试读取文件: %s\n', filepath);
        
        % 检查文件是否存在
        if ~exist(filepath, 'file')
            fprintf('文件不存在: %s\n', filepath);
            continue;
        end
        
        % 仅使用Java ImageIO方法读取
        success = false;
        stroke = [];
        
        try
            import javax.imageio.ImageIO
            java_img = ImageIO.read(java.io.File(filepath));
            width = java_img.getWidth();
            height = java_img.getHeight();
            
            % 获取图像类型
            img_type = java_img.getType();
            fprintf('Java ImageIO读取的图像类型: %d\n', img_type);
            
            % 转换为MATLAB数组
            if img_type == java.awt.image.BufferedImage.TYPE_INT_ARGB || ...
               img_type == java.awt.image.BufferedImage.TYPE_4BYTE_ABGR
                % 包含Alpha通道的图像
                img_data = java_img.getData();
                pixel_array = img_data.getPixels(0, 0, width, height, uint8([]));
                pixel_array = reshape(pixel_array, 4, width*height)';  % RGBA
                
                % 重构图像
                stroke = zeros(height, width, 4, 'uint8');
                stroke(:, :, 1) = reshape(pixel_array(:,1), height, width); % R
                stroke(:, :, 2) = reshape(pixel_array(:,2), height, width); % G
                stroke(:, :, 3) = reshape(pixel_array(:,3), height, width); % B
                stroke(:, :, 4) = reshape(pixel_array(:,4), height, width); % A
            else
                % 不包含Alpha通道的图像，创建全透明通道
                img_rgb = java_img.getRGB(0, 0, width, height, int32([]), 0, width);
                img_rgb = typecast(img_rgb, 'uint8');
                img_rgb = reshape(img_rgb, 4, width*height)';  % ARGB
                
                % 重构图像
                stroke = zeros(height, width, 4, 'uint8');
                stroke(:, :, 1) = reshape(img_rgb(:,3), height, width); % R
                stroke(:, :, 2) = reshape(img_rgb(:,2), height, width); % G
                stroke(:, :, 3) = reshape(img_rgb(:,1), height, width); % B
                stroke(:, :, 4) = reshape(img_rgb(:,4), height, width); % A
            end
            
            success = true;
            fprintf('使用Java ImageIO成功读取图片\n');
        catch err
            fprintf('Java ImageIO方法失败: %s\n', err.message);
        end
        
        % 如果成功读取图像
        if success
            % 显示图片信息
            fprintf('成功读取图片: %s, 尺寸: %dx%d, 通道数: %d\n', ...
                files(i).name, size(stroke, 1), size(stroke, 2), size(stroke, 3));
            
            % 确保图像是uint8类型
            if ~isa(stroke, 'uint8')
                fprintf('警告: 图片 %s 不是 uint8 类型，转换中...\n', files(i).name);
                stroke = im2uint8(mat2gray(stroke));
            end
            
            % 处理不同通道数的图像（确保RGBA格式）
            if size(stroke, 3) == 1
                % 灰度图转RGBA
                stroke = cat(3, repmat(stroke, [1, 1, 3]), uint8(ones(size(stroke,1), size(stroke,2))*255));
            elseif size(stroke, 3) == 3
                % RGB转RGBA
                stroke = cat(3, stroke, uint8(ones(size(stroke,1), size(stroke,2))*255));
            elseif size(stroke, 3) ~= 4
                % 其他情况，强制转换为RGBA
                fprintf('警告: 图片 %s 有 %d 个通道，强制转换为RGBA...\n', files(i).name, size(stroke, 3));
                stroke = cat(3, stroke(:,:,1:3), uint8(ones(size(stroke,1), size(stroke,2))*255));
            end
            
            % 增强白色区域
            if enhance_enable
                stroke = enhance_white(stroke, bright_white_thresh, dark_black_thresh);
            end
            
            strokes{end+1} = stroke;
        end
    end
end

function image = enhance_white(image, bright_thresh, dark_thresh)
    % 增强图像中的白色区域，使其更加明显
    [height, width, ~] = size(image);
    image = double(image);
    
    % 向量化处理，提高性能
    for c = 1:3  % 对RGB通道处理
        % 获取当前通道
        channel = image(:,:,c);
        alpha = image(:,:,4);
        
        % 增强白色区域
        white_mask = (channel > bright_thresh) & (alpha > 0);
        black_mask = (channel < dark_thresh) & (alpha > 0);
        
        channel(white_mask) = 255;
        channel(black_mask) = 0;
        
        % 更新通道
        image(:,:,c) = channel;
    end
    
    image = uint8(image);
end

function canvas = place_stroke(canvas, stroke, position)
    % 在指定位置放置笔画
    [canvas_h, canvas_w, ~] = size(canvas);
    [stroke_h, stroke_w, ~] = size(stroke);
    x = position(1);
    y = position(2);
    
    % 计算有效区域
    start_x = max(1, x);
    start_y = max(1, y);
    end_x = min(canvas_w, x + stroke_w - 1);
    end_y = min(canvas_h, y + stroke_h - 1);
    
    if start_x > end_x || start_y > end_y
        return;  % 无重叠区域，直接返回原画布
    end
    
    % 计算在笔画中的对应区域
    stroke_start_x = start_x - x + 1;
    stroke_start_y = start_y - y + 1;
    stroke_end_x = end_x - x + 1;
    stroke_end_y = end_y - y + 1;
    
    % 提取笔画区域
    stroke_region = stroke(stroke_start_y:stroke_end_y, stroke_start_x:stroke_end_x, :);
    
    % 提取alpha通道并创建掩码
    alpha_mask = stroke_region(:, :, 4) / 255;
    alpha_mask_3d = repmat(alpha_mask, [1, 1, 3]);
    
    % 混合笔画与画布
    canvas_region = canvas(start_y:end_y, start_x:end_x, 1:3);
    blended_region = canvas_region .* (1 - alpha_mask_3d) + stroke_region(:, :, 1:3) .* alpha_mask_3d;
    
    % 更新画布
    canvas(start_y:end_y, start_x:end_x, 1:3) = blended_region;
    % 更新alpha通道（取最大值）
    canvas(start_y:end_y, start_x:end_x, 4) = max(canvas(start_y:end_y, start_x:end_x, 4), stroke_region(:, :, 4));
end

function result = is_overlapping(canvas, stroke, position, threshold)
    % 检查笔画放置在指定位置是否与现有内容重叠超过阈值
    if nargin < 4
        threshold = 0.05;
    end
    
    x = position(1);
    y = position(2);
    [stroke_h, stroke_w, ~] = size(stroke);
    [canvas_h, canvas_w, ~] = size(canvas);
    
    % 检查是否完全超出画布范围
    if x + stroke_w - 1 < 1 || x > canvas_w || y + stroke_h - 1 < 1 || y > canvas_h
        result = true;
        return;
    end
    
    % 计算实际重叠区域
    crop_x1 = max(1, x);
    crop_y1 = max(1, y);
    crop_x2 = min(canvas_w, x + stroke_w - 1);
    crop_y2 = min(canvas_h, y + stroke_h - 1);
    
    % 无实际重叠区域
    if crop_x1 > crop_x2 || crop_y1 > crop_y2
        result = false;
        return;
    end
    
    % 提取重叠区域
    try
        canvas_region = canvas(crop_y1:crop_y2, crop_x1:crop_x2, :);
        stroke_region = stroke(crop_y1 - y + 1:crop_y2 - y + 1, crop_x1 - x + 1:crop_x2 - x + 1, :);
    catch
        result = true;
        return;
    end
    
    % 转换为数组进行重叠检测
    stroke_alpha = stroke_region(:, :, 4) > 10;  % 忽略几乎透明的部分
    total_stroke_area = sum(stroke_alpha(:));
    
    if total_stroke_area == 0
        result = false;
        return;
    end
    
    % 提取画布上的已有笔画区域
    canvas_alpha = canvas_region(:, :, 4) > 10;
    
    % 计算重叠比例
    overlap = logical(and(stroke_alpha, canvas_alpha));
    overlap_ratio = sum(overlap(:)) / total_stroke_area;
    
    result = overlap_ratio > threshold;
end

function size = get_bmp_size(folder_path)
    % 获取文件夹中bmp图片的尺寸作为画布尺寸
    files = dir(fullfile(folder_path, '*.bmp'));
    for i = 1:length(files)
        try
            filepath = fullfile(folder_path, files(i).name);
            info = imfinfo(filepath);
            size = [info.Width, info.Height];
            return;
        catch
            % 忽略错误，继续找下一个BMP
            continue;
        end
    end
    size = [256, 256];  % 默认画布尺寸
end

function coverage = calculate_coverage(canvas)
    % 计算画布被笔画覆盖的比例
    [h, w, ~] = size(canvas);
    canvas_alpha = canvas(:, :, 4) > 10;
    coverage = sum(canvas_alpha(:)) / (w * h);
end

function regions = get_character_regions(canvas_size)
    % 定义汉字可能的笔画分布区域
    w = canvas_size(1);
    h = canvas_size(2);
    
    % 定义主要结构区域（基于汉字的九宫格结构）
    regions = [
        1, 1, floor(w/3), floor(h/3);                  % 左上
        floor(w/3)+1, 1, floor(2*w/3), floor(h/3);     % 中上
        floor(2*w/3)+1, 1, w, floor(h/3);              % 右上
        1, floor(h/3)+1, floor(w/3), floor(2*h/3);     % 左中
        floor(w/3)+1, floor(h/3)+1, floor(2*w/3), floor(2*h/3);  % 中心
        floor(2*w/3)+1, floor(h/3)+1, w, floor(2*h/3); % 右中
        1, floor(2*h/3)+1, floor(w/3), h;              % 左下
        floor(w/3)+1, floor(2*h/3)+1, floor(2*w/3), h; % 中下
        floor(2*w/3)+1, floor(2*h/3)+1, w, h;          % 右下
    ];
end

function position = find_optimal_position(canvas, stroke, regions, max_attempts)
    % 在指定区域内寻找最优放置位置
    if nargin < 4
        max_attempts = 50;
    end
    
    [canvas_h, canvas_w, ~] = size(canvas);
    [stroke_h, stroke_w, ~] = size(stroke);
    
    % 随机打乱区域顺序
    regions = regions(randperm(size(regions, 1)), :);
    
    for r = 1:size(regions, 1)
        region = regions(r, :);
        rx1 = region(1);
        ry1 = region(2);
        rx2 = region(3);
        ry2 = region(4);
        
        % 计算区域内可放置的空间
        region_w = rx2 - rx1 + 1;
        region_h = ry2 - ry1 + 1;
        
        if region_w < stroke_w || region_h < stroke_h
            continue;
        end
        
        for a = 1:max_attempts
            % 在区域内随机选择位置
            x = rx1 + randi(region_w - stroke_w + 1) - 1;
            y = ry1 + randi(region_h - stroke_h + 1) - 1;
            
            % 检查重叠
            if ~is_overlapping(canvas, stroke, [x, y])
                position = [x, y];
                return;
            end
        end
    end
    
    % 如果区域内找不到合适位置，尝试整个画布
    for a = 1:max_attempts
        if canvas_w >= stroke_w && canvas_h >= stroke_h
            x = randi(canvas_w - stroke_w + 1);
            y = randi(canvas_h - stroke_h + 1);
            
            if ~is_overlapping(canvas, stroke, [x, y])
                position = [x, y];
                return;
            end
        end
    end
    
    position = [];  % 无法找到合适位置
end

function importance = calculate_stroke_importance(stroke, canvas_size)
    % 计算笔画对汉字结构的重要性（基于大小和方向）
    [stroke_h, stroke_w, ~] = size(stroke);
    canvas_w = canvas_size(1);
    canvas_h = canvas_size(2);
    
    % 计算笔画占画布的比例
    area_ratio = (stroke_w * stroke_h) / (canvas_w * canvas_h);
    
    % 计算笔画的纵横比
    if min(stroke_w, stroke_h) == 0
        aspect_ratio = 1;
    else
        aspect_ratio = max(stroke_w, stroke_h) / min(stroke_w, stroke_h);
    end
    
    % 判断是否为横/竖笔画
    is_horizontal = stroke_w > stroke_h * 1.5;
    is_vertical = stroke_h > stroke_w * 1.5;
    
    % 重要性评分
    if is_horizontal || is_vertical
        importance = area_ratio * 1.5;
    else
        importance = area_ratio;
    end
end

function assemble_character(strokes, output_path, canvas_size)
    % 组合所有笔画，生成更像汉字的符号
    canvas_w = canvas_size(1);
    canvas_h = canvas_size(2);
    
    % 创建透明背景画布 (RGBA)
    canvas = zeros(canvas_h, canvas_w, 4, 'uint8');
    
    total_strokes = length(strokes);
    
    if total_strokes == 0
        fprintf("没有找到笔画图片\n");
        return;
    end
    
    % 按重要性排序笔画
    [~, order] = sort(cellfun(@(s) calculate_stroke_importance(s, canvas_size), strokes), 'descend');
    strokes = strokes(order);
    
    % 获取汉字区域划分
    regions = get_character_regions(canvas_size);
    
    % 记录每个区域的笔画数量
    region_counts = zeros(1, size(regions, 1));
    
    % 先放置几个关键笔画
    if total_strokes >= 1
        % 第一个笔画：优先放在中心区域
        center_region = regions(5, :);  % 中心区域是第5个
        position = find_optimal_position(canvas, strokes{1}, center_region);
        if ~isempty(position)
            canvas = place_stroke(canvas, strokes{1}, position);
            fprintf("放置笔画 1/%d (中心区域)\n", total_strokes);
        end
    end
    
    if total_strokes >= 2
        % 第二个笔画：优先放在中心区域
        center_region = regions(5, :);
        position = find_optimal_position(canvas, strokes{2}, center_region);
        if ~isempty(position)
            canvas = place_stroke(canvas, strokes{2}, position);
            fprintf("放置笔画 2/%d (中心区域)\n", total_strokes);
        end
    end
    
    % 放置剩余笔画
    for i = 3:total_strokes
        % 计算每个区域的权重
        weights = 1 ./ (region_counts + 1);
        normalized_weights = weights / sum(weights);
        
        % 根据权重选择区域
        selected_idx = randsample(length(weights), min(3, length(weights)), true, normalized_weights);
        selected_regions = regions(selected_idx, :);
        
        position = find_optimal_position(canvas, strokes{i}, selected_regions);
        
        if ~isempty(position)
            canvas = place_stroke(canvas, strokes{i}, position);
            
            % 记录该区域的笔画数量增加
            x = position(1);
            y = position(2);
            for idx = 1:size(regions, 1)
                region = regions(idx, :);
                rx1 = region(1);
                ry1 = region(2);
                rx2 = region(3);
                ry2 = region(4);
                if x >= rx1 && x <= rx2 && y >= ry1 && y <= ry2
                    region_counts(idx) = region_counts(idx) + 1;
                    break;
                end
            end
            
            fprintf("放置笔画 %d/%d (区域: %d)\n", i, total_strokes, selected_idx(1));
        end
    end
    
    % 添加黑色背景（使用 bsxfun 处理维度匹配）
    canvas(:, :, 1:3) = bsxfun(@times, canvas(:, :, 1:3), canvas(:, :, 4)/255);
    
    % 保存结果为BMP
    imwrite(canvas(:, :, 1:3), output_path, 'bmp');
    
    % 计算覆盖率
    coverage = calculate_coverage(canvas);
    fprintf("已生成合成图片: %s\n", output_path);
    fprintf("总笔画数: %d, 覆盖率: %.2f\n", total_strokes, coverage);
end