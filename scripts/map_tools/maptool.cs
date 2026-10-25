using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using System.Windows.Media;
using System.Windows.Media.Imaging;

public static class MapTool {
    // Load any WIC-readable image as 32-bit BGRA.
    public static int[] Load(string path, out int w, out int h) {
        using (var s = File.OpenRead(path)) {
            var dec = BitmapDecoder.Create(s, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
            var src = new FormatConvertedBitmap(dec.Frames[0], PixelFormats.Bgra32, null, 0);
            w = src.PixelWidth; h = src.PixelHeight;
            var px = new int[w * h];
            src.CopyPixels(px, w * 4, 0);
            return px;
        }
    }
    public static void Save(string path, int[] px, int w, int h) {
        var bmp = BitmapSource.Create(w, h, 96, 96, PixelFormats.Bgra32, null, px, w * 4);
        var enc = new PngBitmapEncoder();
        enc.Frames.Add(BitmapFrame.Create(bmp));
        using (var s = File.Create(path)) enc.Save(s);
    }
    public static int[] Crop(int[] px, int w, int x0, int y0, int cw, int ch, int scale) {
        var o = new int[cw * scale * ch * scale];
        for (int y = 0; y < ch * scale; y++)
            for (int x = 0; x < cw * scale; x++)
                o[y * cw * scale + x] = px[(y0 + y / scale) * w + x0 + x / scale];
        return o;
    }
    // Mean absolute RGB difference of image b shifted by (dx,dy) against a, over the overlap.
    public static double Diff(int[] a, int aw, int ah, int[] b, int bw, int bh, int dx, int dy) {
        long sum = 0, n = 0;
        for (int y = 0; y < ah; y += 2) {
            int by = y - dy; if (by < 0 || by >= bh) continue;
            for (int x = 0; x < aw; x += 2) {
                int bx = x - dx; if (bx < 0 || bx >= bw) continue;
                int p = a[y * aw + x], q = b[by * bw + bx];
                sum += Math.Abs(((p >> 16) & 255) - ((q >> 16) & 255)) + Math.Abs(((p >> 8) & 255) - ((q >> 8) & 255)) + Math.Abs((p & 255) - (q & 255));
                n++;
            }
        }
        return n == 0 ? 1e9 : (double)sum / n;
    }
}
