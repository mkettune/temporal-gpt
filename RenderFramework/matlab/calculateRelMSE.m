function result = calculateRelMSE(image, reference)
    
image1 = read_pfm(image, 1);
image2 = read_pfm(reference, 1);

image2_grayscale = mean(image2, 3);
image2_grayscale_rgb = repmat(image2_grayscale, [1 1 3]);

err = (image1 - image2).^2 ./ (1e-3 + image2_grayscale_rgb.^2);

result = 3 * mean(err(:));