function assembleChineseCharacters()
    % 主函数：从笔画图像合成中文字符
    
    % 初始化路径和参数
    INPUT_FOLDER = 'F:/1/Strokes_PNG';
    OUTPUT_FOLDER = 'F:/1/output';
    RANDOM_SEED = [];
    
    % 检查输入文件夹是否存在
    if ~exist(INPUT_FOLDER, 'dir')
        error('输入文件夹不存在: %s', INPUT_FOLDER);
    end
    
    % 设置随机数种子（如果提供）
    if ~isempty(RANDOM_SEED)
        rng(RANDOM_SEED);
    end
    
    % 检查并创建输出文件夹
    if ~exist(OUTPUT_FOLDER, 'dir')
        mkdir(OUTPUT_FOLDER);
        fprintf('创建输出文件夹: %s\n', OUTPUT_FOLDER);
    end
    
    % 查找子文件夹
    subfolders = dir(INPUT_FOLDER);
    valid_subfolders = 0;
    
    fprintf('开始处理输入文件夹: %s\n', INPUT_FOLDER);
    
    % 遍历所有子文件夹
    for i = 1:length(subfolders)
        if subfolders(i).isdir && ~strcmp(subfolders(i).name, '.') && ~strcmp(subfolders(i).name, '..')
            subfolder_path = fullfile(INPUT_FOLDER, subfolders(i).name);
            fprintf('\n正在处理子文件夹 #%d: %s\n', i, subfolder_path);
            
            % 检查子文件夹中是否有PNG文件
            png_files = dir(fullfile(subfolder_path, '*.png'));
            if isempty(png_files)
                fprintf('警告: 子文件夹 %s 中没有PNG文件，跳过\n', subfolder_path);
                continue;
            else
                fprintf('  找到 %d 个PNG文件\n', length(png_files));
            end
            
            % 获取画布尺寸
            canvas_size = getCanvasSize(subfolder_path);
            fprintf('  画布尺寸: %d x %d\n', canvas_size(1), canvas_size(2));
            
            % 加载笔画图像
            strokes = loadStrokes(subfolder_path);
            
            % 合成字符
            if ~isempty(strokes)
                output_path = fullfile(OUTPUT_FOLDER, [subfolders(i).name '.png']);
                fprintf('  正在合成字符，输出路径: %s\n', output_path);
                assembleCharacter(strokes, output_path, canvas_size);
                valid_subfolders = valid_subfolders + 1;
                fprintf('字符合成完成\n');
            else
                fprintf('警告: 子文件夹 %s 中没有有效的笔画图像，跳过\n', subfolder_path);
            end
        end
    end
    
    % 输出处理结果摘要
    if valid_subfolders == 0
        fprintf('\n错误: 没有找到有效的子文件夹或笔画图像\n');
    else
        fprintf('\n处理完成，共生成 %d 个合成图像\n', valid_subfolders);
    end
    
    % --------------------------------------------------------
    function strokes = loadStrokes(folder_path)
        % 从指定文件夹加载所有PNG格式的笔画图像
        strokes = {};
        files = dir(fullfile(folder_path, '*.png'));
        
        fprintf('  正在加载笔画图像...\n');
        
        % 遍历所有PNG文件
        for i = 1:length(files)
            filepath = fullfile(folder_path, files(i).name);
            
            try
                % 使用MATLAB内置函数读取PNG图像
                img = imread(filepath);
                
                % 处理不同类型的图像（灰度图、RGB图、RGBA图）
                if ndims(img) == 2
                    % 灰度图转RGB
                    img = cat(3, img, img, img);
                    alpha = uint8(ones(size(img, 1), size(img, 2)) * 255);
                elseif ndims(img) == 3 && size(img, 3) == 3
                    % RGB图像添加全不透明alpha通道
                    alpha = uint8(ones(size(img, 1), size(img, 2)) * 255);
                elseif ndims(img) == 3 && size(img, 3) == 4
                    % RGBA图像分离alpha通道
                    alpha = img(:,:,4);
                    img = img(:,:,1:3);
                else
                    error('不支持的图像格式');
                end
                
                % 合并RGB和alpha通道
                stroke = cat(3, img, alpha);
                
                % 增强白色区域
                stroke = enhanceWhite(stroke);
                strokes{end+1} = stroke;
                fprintf('成功加载: %s\n', files(i).name);
            catch e
                fprintf('错误: 无法加载 %s - %s\n', files(i).name, e.message);
                % 尝试获取图像信息
                try
                    info = imfinfo(filepath);
                    fprintf('图像信息: 宽度=%d, 高度=%d, 位深=%d, 格式=%s\n', info.Width, info.Height, info.BitDepth, info.Format);
                catch
                    fprintf('无法获取图像信息\n');
                end
                continue; % 跳过有问题的文件
            end
        end
        
        fprintf('从 %s 加载了 %d 个有效笔画\n', folder_path, length(strokes));
    end
    
    % --------------------------------------------------------
    function img = enhanceWhite(image)
        % 增强图像中的白色区域
        alpha = image(:,:,4);
        alpha_mask = alpha > 0;
        
        % 计算亮度
        brightness = mean(image(:,:,1:3), 3);
        
        % 找出亮区和暗区像素
        bright_pixels = brightness > 220 & alpha_mask;
        dark_pixels = brightness < 50 & alpha_mask;
        
        % 亮区设为白色，暗区设为黑色
        for c = 1:3
            channel = image(:,:,c);
            channel(bright_pixels) = 255;
            channel(dark_pixels) = 0;
            image(:,:,c) = uint8(channel);
        end
        
        img = image;
    end
    
    % --------------------------------------------------------
    function resized = resizeStroke(stroke, targetSize, preserveAspectRatio)
        % 调整笔画大小，可选择保持宽高比
        if nargin < 3
            preserveAspectRatio = true;
        end
        
        [h, w, ~] = size(stroke);
        targetW = targetSize(1);
        targetH = targetSize(2);
        
        % 保持宽高比调整大小
        if preserveAspectRatio
            scaleX = targetW / w;
            scaleY = targetH / h;
            scale = min(scaleX, scaleY);
            newW = round(w * scale);
            newH = round(h * scale);
        else
            newW = targetW;
            newH = targetH;
        end
        
        % 使用lanczos3方法调整图像大小
        resized = imresize(stroke, [newH newW], 'lanczos3');
    end
    
    % --------------------------------------------------------
    function canvas = placeStroke(canvas, stroke, position)
        % 将笔画放置在画布上指定位置，并进行alpha通道混合
        x = position(1);
        y = position(2);
        [h, w, ~] = size(stroke);
        
        % 确保位置在画布范围内
        x = max(1, x);
        y = max(1, y);
        
        % 计算在画布中的有效区域
        xEnd = min(x + w - 1, size(canvas, 2));
        yEnd = min(y + h - 1, size(canvas, 1));
        
        % 计算在笔画中的对应区域
        wValid = xEnd - x + 1;
        hValid = yEnd - y + 1;
        
        if wValid <= 0 || hValid <= 0
            return; % 没有可放置的区域
        end
        
        % 提取有效区域
        strokeValid = stroke(1:hValid, 1:wValid, :);
        canvasRegion = canvas(y:yEnd, x:xEnd, :);
        
        % 执行alpha通道混合
        alpha = double(strokeValid(:,:,4)) / 255;
        alpha = repmat(alpha, [1 1 3]);
        
        for c = 1:3
            canvasCh = double(canvasRegion(:,:,c));
            strokeCh = double(strokeValid(:,:,c));
            canvasCh = (1-alpha) .* canvasCh + alpha .* strokeCh;
            canvasRegion(:,:,c) = uint8(canvasCh);
        end
        
        % 更新画布
        canvas(y:yEnd, x:xEnd, :) = canvasRegion;
    end
    
    % --------------------------------------------------------
    function overlapping = isOverlapping(canvas, stroke, position, threshold)
        % 检查笔画放置位置是否与已有内容重叠
        if nargin < 4
            threshold = 0.1;
        end
        
        x = position(1);
        y = position(2);
        [h, w, ~] = size(stroke);
        
        % 检查位置是否有效
        if x < 1 || y < 1 || (x + w - 1) > size(canvas, 2) || (y + h - 1) > size(canvas, 1)
            overlapping = true;
            return;
        end
        
        % 提取笔画的alpha通道（透明度大于50的像素视为可见）
        strokeAlpha = stroke(:,:,4) > 50;
        totalStrokeArea = sum(strokeAlpha(:));
        
        if totalStrokeArea == 0
            overlapping = false;
            return;
        end
        
        % 提取画布区域
        canvasRegion = canvas(y:y+h-1, x:x+w-1, :);
        canvasBrightness = mean(canvasRegion(:,:,1:3), 3);
        canvasNonTransparent = canvasBrightness < 240;  % 亮度小于240的像素视为非透明
        
        % 计算重叠区域
        overlap = strokeAlpha & canvasNonTransparent;
        overlapRatio = sum(overlap(:)) / totalStrokeArea;
        
        overlapping = overlapRatio > threshold;
    end
    
    % --------------------------------------------------------
    function [horizontal, vertical, others] = groupStrokesByType(strokes)
        % 按笔画类型（水平、垂直、其他）分组
        horizontal = {};
        vertical = {};
        others = {};
        
        for i = 1:length(strokes)
            stroke = strokes{i};
            [h, w, ~] = size(stroke);
            
            % 计算宽高比
            aspectRatio = w / h;
            
            % 根据宽高比分类
            if aspectRatio > 2
                horizontal{end+1} = stroke;
            elseif aspectRatio < 0.5
                vertical{end+1} = stroke;
            else
                others{end+1} = stroke;
            end
        end
    end
    
    % --------------------------------------------------------
    function size = getCanvasSize(folder_path)
        % 从第一个有效图像获取画布尺寸，否则使用默认值
        files = dir(fullfile(folder_path, '*.png'));
        size = [500, 500]; % 默认尺寸
        
        % 尝试从文件获取尺寸
        for i = 1:length(files)
            try
                info = imfinfo(fullfile(folder_path, files(i).name));
                size = [info.Width, info.Height];
                fprintf('  从 %s 获取画布尺寸: %d x %d\n', files(i).name, size(1), size(2));
                break;
            catch
                fprintf('  警告: 无法读取 %s 的尺寸，使用默认值\n', files(i).name);
                continue;
            end
        end
    end
    
    % --------------------------------------------------------
    function [canvas, placedStroke] = placeStrokeWithStrategy(canvas, stroke, canvasSize, strategy, maxAttempts)
        % 使用指定策略将笔画放置在画布上
        if nargin < 5
            maxAttempts = 50;
        end
        
        % 调整笔画大小
        targetSize = [canvasSize(1) * 0.8, canvasSize(2) * 0.8];
        placedStroke = resizeStroke(stroke, targetSize);
        [strokeH, strokeW, ~] = size(placedStroke);
        
        % 计算可用空间
        maxX = canvasSize(1) - strokeW + 1;
        maxY = canvasSize(2) - strokeH + 1;
        
        % 如果笔画太大，重新调整大小
        if maxX <= 0 || maxY <= 0
            placedStroke = resizeStroke(stroke, canvasSize, false);
            [strokeH, strokeW, ~] = size(placedStroke);
            maxX = 1;
            maxY = 1;
        end
        
        % 根据策略确定放置位置
        for attempt = 1:maxAttempts
            switch strategy
                case 'center'
                    % 居中放置
                    x = round((canvasSize(1) - strokeW) / 2);
                    y = round((canvasSize(2) - strokeH) / 2);
                    
                case 'random'
                    % 随机放置
                    x = randi([1, maxX]);
                    y = randi([1, maxY]);
                    
                case 'edge'
                    % 边缘放置
                    edges = {'left', 'right', 'top', 'bottom'};
                    edge = edges{randi(4)};
                    
                    switch edge
                        case 'left'
                            x = 1;
                            y = randi([1, maxY]);
                        case 'right'
                            x = maxX;
                            y = randi([1, maxY]);
                        case 'top'
                            x = randi([1, maxX]);
                            y = 1;
                        case 'bottom'
                            x = randi([1, maxX]);
                            y = maxY;
                    end
                    
                otherwise % 默认居中
                    x = round((canvasSize(1) - strokeW) / 2);
                    y = round((canvasSize(2) - strokeH) / 2);
            end
            
            % 检查重叠
            if ~isOverlapping(canvas, placedStroke, [x, y])
                canvas = placeStroke(canvas, placedStroke, [x, y]);
                fprintf('  笔画放置成功 (策略: %s, 尝试次数: %d)\n', strategy, attempt);
                return;
            end
        end
        
        % 如果所有尝试都失败，放置在中心
        x = round((canvasSize(1) - strokeW) / 2);
        y = round((canvasSize(2) - strokeH) / 2);
        canvas = placeStroke(canvas, placedStroke, [x, y]);
        fprintf('  笔画放置 (策略: %s) - 尝试次数用尽，放置在中心\n', strategy);
    end
    
    % --------------------------------------------------------
    function assembleCharacter(strokes, output_path, canvas_size)
        % 从多个笔画合成完整字符
        fprintf('  开始合成字符...\n');
        
        % 创建白色画布
        canvas = uint8(ones([canvas_size(2), canvas_size(1), 3]) * 255);
        
        % 检查是否有可用笔画
        if isempty(strokes)
            fprintf('  错误: 没有可用的笔画图像\n');
            return;
        end
        
        % 按笔画类型分组
        [horizontal, vertical, others] = groupStrokesByType(strokes);
        
        % 按大小排序（从大到小）
        allStrokes = [horizontal; vertical; others];
        strokeAreas = zeros(length(allStrokes), 1);
        
        for i = 1:length(allStrokes)
            alpha = allStrokes{i}(:,:,4) > 0;
            strokeAreas(i) = sum(alpha(:));
        end
        
        [~, sortedIdx] = sort(strokeAreas, 'descend');
        sortedStrokes = allStrokes(sortedIdx);
        
        fprintf('  笔画按大小和类型排序完成\n');
        
        % 先放置主要笔画
        mainStrokesCount = min(3, length(sortedStrokes));
        
        for i = 1:mainStrokesCount
            fprintf('  处理主笔画 #%d...\n', i);
            
            % 为主要笔画使用不同策略
            strategy = 'center';
            if i == 1
                strategy = 'center';
            elseif i == 2
                strategy = 'edge';
            elseif i == 3
                strategy = 'random';
            end
            
            [canvas, ~] = placeStrokeWithStrategy(canvas, sortedStrokes{i}, canvas_size, strategy);
        end
        
        % 放置剩余次要笔画
        for i = mainStrokesCount+1:length(sortedStrokes)
            fprintf('  处理次要笔画 #%d...\n', i - mainStrokesCount);
            
            % 使用随机策略放置次要笔画
            [canvas, ~] = placeStrokeWithStrategy(canvas, sortedStrokes{i}, canvas_size, 'random');
        end
        
        % 保存合成结果
        try
            imwrite(canvas, output_path);
            fprintf('成功保存合成图像到: %s\n', output_path);
        catch e
            fprintf('错误: 无法保存图像 - %s\n', e.message);
        end
    end
end