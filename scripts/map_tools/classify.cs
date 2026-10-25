using System;
using System.Collections.Generic;

// Map classes: 0 sky, 1 cave background, 2 rock, 3 grass, 4 road, 5 underground.
public static class Classify {
    public const int SKY = 0, CAVE = 1, ROCK = 2, GRASS = 3, ROAD = 4, DARK = 5;
    public static readonly int[] Preview = { 0x4F668E, 0x15241C, 0x33536F, 0x40A01F, 0x3F4442, 0x111111 };

    // Night-sky rule for darker screenshots: blue well above green is sky or background
    // scenery, slightly blue is rock, green-leaning is cave. Negative disables it.
    public static int SkyBlueMargin = -1;
    public const int UNKNOWN = 7;

    public static int Pixel(int p) {
        int r = (p >> 16) & 255, g = (p >> 8) & 255, b = p & 255;
        if (g > r + 30 && g > b + 20) return GRASS;
        if (Math.Abs(r - g) < 12 && Math.Abs(g - b) < 12) return (r + g + b) / 3 > 45 ? ROAD : DARK;
        if (SkyBlueMargin >= 0) return g >= b ? CAVE : (b - g >= SkyBlueMargin ? SKY : ROCK);
        if (b > g && r < 0.67 * g) return ROCK;
        if (r >= 0.67 * g && b >= g) return SKY;
        return CAVE;
    }

    // UI buttons and the captioned bottom edge of each shot.
    static bool Overlay(int x, int y, int h) {
        return (x >= 366 && x < 588 && y < 82) || (x >= 862 && y < 172) || y >= h - 14 || y < 10;
    }

    // Two shots placed at (ax, ay) and (bx, by); pixels under either shot's UI come from the other.
    // Returns raw pixels when raw is true, otherwise classes.
    public static int[] Place(int[] a, int aw, int ah, int ax, int ay, int[] b, int bw, int bh, int bx, int by, bool raw, out int w, out int h) {
        w = Math.Max(ax + aw, bx + bw); h = Math.Max(ay + ah, by + bh);
        var o = new int[w * h];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++) {
                int qx = x - ax, qy = y - ay, rx = x - bx, ry = y - by;
                bool inA = qx >= 0 && qx < aw && qy >= 0 && qy < ah, inB = rx >= 0 && rx < bw && ry >= 0 && ry < bh;
                bool okA = inA && !Ui(qx, qy, aw, ah), okB = inB && !Ui(rx, ry, bw, bh);
                int p = okA ? a[qy * aw + qx] : okB ? b[ry * bw + rx] : inA ? a[qy * aw + qx] : inB ? b[ry * bw + rx] : 0;
                o[y * w + x] = raw ? (inA || inB ? p : unchecked((int)0xFF000000)) : (okA || okB ? Pixel(p) : UNKNOWN);
            }
        return o;
    }

    // Pixels no shot covers take the class of the nearest covered pixel below them.
    public static void FillUnknownDown(int[] c, int w, int h) {
        for (int x = 0; x < w; x++)
            for (int y = h - 2; y >= 0; y--)
                if (c[y * w + x] == UNKNOWN) c[y * w + x] = c[(y + 1) * w + x];
        // Rows below every shot copy the covered pixel above.
        for (int x = 0; x < w; x++)
            for (int y = 1; y < h; y++)
                if (c[y * w + x] == UNKNOWN) c[y * w + x] = c[(y - 1) * w + x];
    }

    // Pixels no shot covers take the class of the nearest covered pixel (breadth-first, 4-neighbour).
    public static void FillUnknownNearest(int[] c, int w, int h) {
        var queue = new Queue<int>();
        for (int i = 0; i < c.Length; i++) if (c[i] != UNKNOWN) queue.Enqueue(i);
        while (queue.Count > 0) {
            int p = queue.Dequeue(), x = p % w, y = p / w;
            foreach (var q in new[] { x > 0 ? p - 1 : -1, x < w - 1 ? p + 1 : -1, y > 0 ? p - w : -1, y < h - 1 ? p + w : -1 })
                if (q >= 0 && c[q] == UNKNOWN) { c[q] = c[p]; queue.Enqueue(q); }
        }
    }

    // Removes runs of class k at most maxRun long, horizontally or vertically, whose two ends
    // touch the same other class (thin seams left along UI edges).
    public static void CleanThin(int[] c, int w, int h, int k, int maxRun) {
        for (int pass = 0; pass < 2; pass++) {
            bool vertical = pass == 1;
            int lines = vertical ? w : h, len = vertical ? h : w;
            for (int l = 0; l < lines; l++) {
                int i = 0;
                while (i < len) {
                    int p = vertical ? i * w + l : l * w + i;
                    if (c[p] != k) { i++; continue; }
                    int j = i; while (j < len && c[vertical ? j * w + l : l * w + j] == k) j++;
                    if (i > 0 && j < len && j - i <= maxRun) {
                        int before = c[vertical ? (i - 1) * w + l : l * w + i - 1], after = c[vertical ? j * w + l : l * w + j];
                        if (before == after) for (int m = i; m < j; m++) c[vertical ? m * w + l : l * w + m] = before;
                    }
                    i = j;
                }
            }
        }
    }

    // Bubble buttons along the top centre and the play button top right.
    static bool Ui(int x, int y, int w, int h) {
        return (x >= 360 && x < 592 && y < 82) || (x >= w - 82 && y < 82);
    }

    // Mode filter over a (2r+1)^2 window; grass is kept and ignored when voting.
    public static int[] Smooth(int[] c, int w, int h, int r) {
        var o = new int[c.Length];
        var n = new int[6];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++) {
                int p = c[y * w + x];
                if (p == GRASS) { o[y * w + x] = p; continue; }
                Array.Clear(n, 0, 6);
                for (int j = Math.Max(0, y - r); j <= Math.Min(h - 1, y + r); j++)
                    for (int i = Math.Max(0, x - r); i <= Math.Min(w - 1, x + r); i++) n[c[j * w + i]]++;
                n[GRASS] = 0;
                int best = p; for (int k = 0; k < 6; k++) if (n[k] > n[best]) best = k;
                o[y * w + x] = best;
            }
        return o;
    }

    public static void Fill(int[] c, int w, int x0, int y0, int x1, int y1, int k) {
        for (int y = y0; y < y1; y++) for (int x = x0; x < x1; x++) c[y * w + x] = k;
    }

    // Merge the two shots (shot 2 placed at dx, dy) into one class grid, avoiding UI overlays.
    public static int[] Merge(int[] a, int aw, int ah, int[] b, int bw, int bh, int dx, int dy, out int w, out int h) {
        w = Math.Max(aw, bw + dx); h = Math.Max(ah, bh + dy);
        var o = new int[w * h];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++) {
                bool inA = x < aw && y < ah, inB = x - dx >= 0 && x - dx < bw && y - dy >= 0 && y - dy < bh;
                bool okA = inA && !Overlay(x, y, ah), okB = inB && !Overlay(x - dx, y - dy, bh);
                o[y * w + x] = okA ? Pixel(a[y * aw + x]) : okB ? Pixel(b[(y - dy) * bw + x - dx]) : SKY;
            }
        return o;
    }

    // Majority class over each s by s block.
    public static int[] Down(int[] c, int w, int h, int s, out int ow, out int oh) {
        ow = w / s; oh = h / s;
        var o = new int[ow * oh];
        for (int y = 0; y < oh; y++)
            for (int x = 0; x < ow; x++) {
                var n = new int[6];
                for (int j = 0; j < s; j++) for (int i = 0; i < s; i++) n[c[(y * s + j) * w + x * s + i]]++;
                int best = 0; for (int k = 1; k < 6; k++) if (n[k] > n[best]) best = k;
                // Keep thin grass lines: any grass in the block wins over cave/sky.
                if (n[GRASS] * 4 >= s * s && best != ROCK) best = GRASS;
                o[y * ow + x] = best;
            }
        return o;
    }

    // Replace components smaller than minSize of class k by the most common neighbouring class.
    public static void RemoveSmall(int[] c, int w, int h, int k, int minSize) {
        var seen = new bool[w * h];
        for (int start = 0; start < w * h; start++) {
            if (seen[start] || c[start] != k) continue;
            var comp = new List<int>(); var stack = new Stack<int>(); stack.Push(start); seen[start] = true;
            var n = new int[6];
            while (stack.Count > 0) {
                int p = stack.Pop(); comp.Add(p);
                int x = p % w, y = p / w;
                foreach (var q in new[] { x > 0 ? p - 1 : -1, x < w - 1 ? p + 1 : -1, y > 0 ? p - w : -1, y < h - 1 ? p + w : -1 }) {
                    if (q < 0) continue;
                    if (c[q] == k) { if (!seen[q]) { seen[q] = true; stack.Push(q); } }
                    else n[c[q]]++;
                }
            }
            if (comp.Count >= minSize) continue;
            int best = k == 0 ? 1 : 0; for (int j = 0; j < 6; j++) if (j != k && n[j] > n[best]) best = j;
            foreach (int p in comp) c[p] = best;
        }
    }

    public static int[] Colour(int[] c) {
        var o = new int[c.Length];
        for (int i = 0; i < c.Length; i++) o[i] = unchecked((int)0xFF000000) | Preview[c[i]];
        return o;
    }
}
