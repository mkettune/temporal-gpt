% PFM writer -- copes with both 1- and 3-channel images
%
function write_pfm(img, fname, flip)

if nargin < 3
    flip = true;  % default value for compatibility with Dali and HDRShop
    if 0
        warning('write_pfm implicitely flips image');
    else
        error('you have to specify whether your PFM format is flipped (whether its origin is bottom-left)');
    end
end

num_channels = size(img,3);
if num_channels == 1
    if flip
        img = flipud(img);
    end
    I = img';
    pfm_id = 'Pf';
else
    if flip
        img(:,:,1) = flipud(img(:,:,1));
        img(:,:,2) = flipud(img(:,:,2));
        img(:,:,3) = flipud(img(:,:,3));
    end
    I = permute(img, [ 3 2 1 ]);
    pfm_id = 'PF';
end
fid = fopen(fname, 'wb');
fprintf(fid, sprintf('%s\n%d %d\n-1.0\n', pfm_id, size(img,2), size(img,1)));
fwrite(fid, I, 'float', 0, 'ieee-le');    % always dump little endian (hence negative scale of -1.0)
fclose(fid);

% $Id: write_pfm.m,v 1.2 2008/12/31 10:27:46 tw-mmill Exp $
%
% copyright (c) 2003--2004, Tim Weyrich
% Computer Graphics Lab, ETH Zurich
%
% $Log: write_pfm.m,v $
% Revision 1.2  2008/12/31 10:27:46  tw-mmill
% PFM rader and writer now force specification of flip flag
%
% Revision 1.1  2008/11/14 18:53:12  tw-mmill
% generating test height field with tilted blocks
%
% Revision 1.1.1.1  2004/08/09 13:01:00  weyrich
% initial check-in of all .m files
%
%
