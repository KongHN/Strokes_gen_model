function assembleChineseCharacters()
    % Main function to assemble Chinese characters from strokes
    
    % Initialize paths and parameters
    INPUT_FOLDER = 'F:/1/Strokes_PNG';
    OUTPUT_FOLDER = 'F:/1/output';
    RANDOM_SEED = [];
    
    % 检查输入文件夹是否存在
    if ~exist(INPUT_FOLDER, 'dir')
        error('输入文件夹不存在: %s', INPUT_FOLDER);
    end
    
    if ~isempty(RANDOM_SEED)
        rng(RANDOM_SEED);
    end
    
    if ~exist(OUTPUT_FOLDER, 'dir')
        mkdir(OUTPUT_FOLDER);
        fprintf('创建输出文件夹: %s\n', OUTPUT_FOLDER);
    end
    
    % 查找子文件夹
    subfolders = dir(INPUT_FOLDER);
    valid_subfolders = 0;
    
    fprintf('开始处理输入文件夹: %s\n', INPUT_FOLDER);
    
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
            
            % 加载笔画
            strokes = loadStrokes(subfolder_path);
            
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
    
    if valid_subfolders == 0
        fprintf('\n错误: 没有找到有效的子文件夹或笔画图像\n');
    else
        fprintf('\n处理完成，共生成 %d 个合成图像\n', valid_subfolders);
    end
end

function strokes = loadStrokes(folder_path)
    % Load all PNG stroke images from the specified folder
    strokes = {};
    files = dir(fullfile(folder_path, '*.png'));
    
    fprintf('  正在加载笔画图像...\n');
    
    for i = 1:length(files)
        filepath = fullfile(folder_path, files(i).name);
        
        try
            % 使用MATLAB内置函数读取PNG
            img = imread(filepath);
            
            % 检查图像维度
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
            % 尝试使用imfinfo获取更多信息
            try
                info = imfinfo(filepath);
                fprintf('图像信息: 宽度=%d, 高度=%d, 位深=%d, 格式=%s\n', info.Width, info.Height, info.BitDepth, info.Format);
            catch
                fprintf('无法获取图像信息\n');
            end
            continue; % Skip problematic files
        end
    end
    
    fprintf('从 %s 加载了 %d 个有效笔画\n', folder_path, length(strokes));
end

function img = enhanceWhite(image)
    % Enhance white regions in the image
    alpha = image(:,:,4);
    alpha_mask = alpha > 0;
    
    % Calculate brightness
    brightness = mean(image(:,:,1:3), 3);
    
    % Find bright and dark pixels
    bright_pixels = brightness > 220 & alpha_mask;
    dark_pixels = brightness < 50 & alpha_mask;
    
    % Set white for bright pixels and black for dark pixels
    for c = 1:3
        channel = image(:,:,c);
        channel(bright_pixels) = 255;
        channel(dark_pixels) = 0;
        image(:,:,c) = uint8(channel);
    end
    
    img = image;
end

function resized = resizeStroke(stroke, targetSize, preserveAspectRatio)
    % Resize stroke with aspect ratio preservation
    if nargin < 3
        preserveAspectRatio = true;
    end
    
    [h, w, ~] = size(stroke);
    targetW = targetSize(1);
    targetH = targetSize(2);
    
    if preserveAspectRatio
        % Calculate scaling factors
        scaleX = targetW / w;
        scaleY = targetH / h;
        
        % Use the smaller scale to ensure the stroke fits within the target size
        scale = min(scaleX, scaleY);
        
        % Calculate new size
        newW = round(w * scale);
        newH = round(h * scale);
    else
        newW = targetW;
        newH = targetH;
    end
    
    % Resize the image
    resized = imresize(stroke, [newH newW], 'lanczos3');
end

function canvas = placeStroke(canvas, stroke, position)
    % Place stroke on canvas at specified position with alpha blending
    x = position(1);
    y = position(2);
    [h, w, ~] = size(stroke);
    
    % Ensure position is within canvas bounds
    x = max(1, x);
    y = max(1, y);
    
    % Calculate valid region in canvas
    xEnd = min(x + w - 1, size(canvas, 2));
    yEnd = min(y + h - 1, size(canvas, 1));
    
    % Calculate corresponding region in stroke
    wValid = xEnd - x + 1;
    hValid = yEnd - y + 1;
    
    if wValid <= 0 || hValid <= 0
        return; % Nothing to place
    end
    
    % Extract valid regions
    strokeValid = stroke(1:hValid, 1:wValid, :);
    canvasRegion = canvas(y:yEnd, x:xEnd, :);
    
    % Perform alpha blending
    alpha = double(strokeValid(:,:,4)) / 255;
    alpha = repmat(alpha, [1 1 3]);
    
    for c = 1:3
        canvasCh = double(canvasRegion(:,:,c));
        strokeCh = double(strokeValid(:,:,c));
        canvasCh = (1-alpha) .* canvasCh + alpha .* strokeCh;
        canvasRegion(:,:,c) = uint8(canvasCh);
    end
    
    % Update canvas
    canvas(y:yEnd, x:xEnd, :) = canvasRegion;
end

function overlapping = isOverlapping(canvas, stroke, position, threshold)
    % Check if stroke overlaps with existing content
    if nargin < 4
        threshold = 0.1;
    end
    
    x = position(1);
    y = position(2);
    [h, w, ~] = size(stroke);
    
    % Check if position is valid
    if x < 1 || y < 1 || (x + w - 1) > size(canvas, 2) || (y + h - 1) > size(canvas, 1)
        overlapping = true;
        return;
    end
    
    % Extract regions
    strokeAlpha = stroke(:,:,4) > 50;  % Consider pixels with alpha > 50 as visible
    totalStrokeArea = sum(strokeAlpha(:));
    
    if totalStrokeArea == 0
        overlapping = false;
        return;
    end
    
    % Extract canvas region
    canvasRegion = canvas(y:y+h-1, x:x+w-1, :);
    canvasBrightness = mean(canvasRegion(:,:,1:3), 3);
    canvasNonTransparent = canvasBrightness < 240;  % Consider pixels darker than 240 as non-transparent
    
    % Calculate overlap
    overlap = strokeAlpha & canvasNonTransparent;
    overlapRatio = sum(overlap(:)) / totalStrokeArea;
    
    overlapping = overlapRatio > threshold;
end

function [horizontal, vertical, others] = groupStrokesByType(strokes)
    % Group strokes by their type (horizontal, vertical, others)
    horizontal = {};
    vertical = {};
    others = {};
    
    for i = 1:length(strokes)
        stroke = strokes{i};
        [h, w, ~] = size(stroke);
        
        % Calculate aspect ratio
        aspectRatio = w / h;
        
        if aspectRatio > 2
            horizontal{end+1} = stroke;
        elseif aspectRatio < 0.5
            vertical{end+1} = stroke;
        else
            others{end+1} = stroke;
        end
    end
end

function size = getCanvasSize(folder_path)
    % Get canvas size from the first valid image or use default
    files = dir(fullfile(folder_path, '*.png'));
    size = [500, 500]; % Default size
    
    for i = 1:length(files)
        try
            info = imfinfo(filepath);
            size = [info.Width, info.Height];
            fprintf('  从 %s 获取画布尺寸: %d x %d\n', files(i).name, size(1), size(2));
            break;
        catch
            fprintf('  警告: 无法读取 %s 的尺寸，使用默认值\n', files(i).name);
            continue;
        end
    end
end

function [canvas, placedStroke] = placeStrokeWithStrategy(canvas, stroke, canvasSize, strategy, maxAttempts)
    % Place stroke on canvas using specified strategy
    if nargin < 5
        maxAttempts = 50;
    end
    
    % Resize stroke to a reasonable size
    targetSize = [canvasSize(1) * 0.8, canvasSize(2) * 0.8];
    placedStroke = resizeStroke(stroke, targetSize);
    [strokeH, strokeW, ~] = size(placedStroke);
    
    % Calculate available space
    maxX = canvasSize(1) - strokeW + 1;
    maxY = canvasSize(2) - strokeH + 1;
    
    if maxX <= 0 || maxY <= 0
        % Stroke is too large for canvas, resize again
        placedStroke = resizeStroke(stroke, canvasSize, false);
        [strokeH, strokeW, ~] = size(placedStroke);
        maxX = 1;
        maxY = 1;
    end
    
    % Determine placement based on strategy
    for attempt = 1:maxAttempts
        switch strategy
            case 'center'
                x = round((canvasSize(1) - strokeW) / 2);
                y = round((canvasSize(2) - strokeH) / 2);
                
            case 'random'
                x = randi([1, maxX]);
                y = randi([1, maxY]);
                
            case 'edge'
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
                
            otherwise % default to center
                x = round((canvasSize(1) - strokeW) / 2);
                y = round((canvasSize(2) - strokeH) / 2);
        end
        
        % Check overlap
        if ~isOverlapping(canvas, placedStroke, [x, y])
            canvas = placeStroke(canvas, placedStroke, [x, y]);
            fprintf('  笔画放置成功 (策略: %s, 尝试次数: %d)\n', strategy, attempt);
            return;
        end
    end
    
    % If all attempts failed, place at center
    x = round((canvasSize(1) - strokeW) / 2);
    y = round((canvasSize(2) - strokeH) / 2);
    canvas = placeStroke(canvas, placedStroke, [x, y]);
    fprintf('  笔画放置 (策略: %s) - 尝试次数用尽，放置在中心\n', strategy);
end

function assembleCharacter(strokes, output_path, canvas_size)
    % Assemble character from strokes with improved strategy
    fprintf('  开始合成字符...\n');
    
    % Create white canvas
    canvas = uint8(ones([canvas_size(2), canvas_size(1), 3]) * 255);
    
    if isempty(strokes)
        fprintf('  错误: 没有可用的笔画图像\n');
        return;
    end
    
    % Group strokes by type
    [horizontal, vertical, others] = groupStrokesByType(strokes);
    
    % Sort strokes by size (largest first)
    allStrokes = [horizontal; vertical; others];
    strokeAreas = zeros(length(allStrokes), 1);
    
    for i = 1:length(allStrokes)
        alpha = allStrokes{i}(:,:,4) > 0;
        strokeAreas(i) = sum(alpha(:));
    end
    
    [~, sortedIdx] = sort(strokeAreas, 'descend');
    sortedStrokes = allStrokes(sortedIdx);
    
    fprintf('  笔画按大小和类型排序完成\n');
    
    % Place main strokes first
    mainStrokesCount = min(3, length(sortedStrokes));
    
    for i = 1:mainStrokesCount
        fprintf('  处理主笔画 #%d...\n', i);
        
        % Use different strategies for main strokes
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
    
    % Place remaining strokes
    for i = mainStrokesCount+1:length(sortedStrokes)
        fprintf('  处理次要笔画 #%d...\n', i - mainStrokesCount);
        
        % Use random placement with overlap check
        [canvas, ~] = placeStrokeWithStrategy(canvas, sortedStrokes{i}, canvas_size, 'random');
    end
    
    % Save result
    try
        imwrite(canvas, output_path);
        fprintf('成功保存合成图像到: %s\n', output_path);
    catch e
        fprintf('错误: 无法保存图像 - %s\n', e.message);
    end
end    