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

    // Smooth the traced terrain so the vehicle rolls instead of bumping. Returns the solid
    // mask (decorative grass stays open) and recolours every pixel whose solidity changed
    // from its original neighbours, so drawing and collision keep the same shape.
    //  1. Twice, each floor top (solid with at least 4 solid pixels below, open above)
    //     moves to the median height of the floor tops within 4 columns either side
    //     (nearest top within 3 rows); floor ends with fewer than 5 tops are left alone.
    //     This removes lumps and dips up to 4 columns wide but keeps real steps and slopes.
    //  2. Closing with a radius-3 disk fills notches; opening with a radius-2 disk removes
    //     spikes and crumbs. Above the map is open and below it solid; beyond the left and
    //     right edges the edge column continues, so terrain is not eaten at the world sides.
    public static bool[] SmoothTerrain(int[] c, bool[] decor, int w, int h) {
        var solid = new bool[w * h];
        for (int i = 0; i < w * h; i++) solid[i] = c[i] >= ROCK && c[i] <= DARK && !decor[i];
        var m = solid;
        for (int pass = 0; pass < 2; pass++) m = FloorMedian(m, w, h, 4, 4, 3);
        m = Dilate(Erode(Erode(Dilate(m, w, h, 3), w, h, 3), w, h, 2), w, h, 2);
        for (int i = 0; i < w * h; i++) if (decor[i]) m[i] = false;
        var original = (int[])c.Clone();
        var n = new int[6];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++) {
                int p = y * w + x;
                if (m[p] == solid[p]) continue;
                Array.Clear(n, 0, 6);
                for (int j = Math.Max(0, y - 2); j <= Math.Min(h - 1, y + 2); j++)
                    for (int i = Math.Max(0, x - 2); i <= Math.Min(w - 1, x + 2); i++)
                        if (solid[j * w + i] == m[p] && !decor[j * w + i]) n[original[j * w + i]]++;
                int best = m[p] ? ROCK : CAVE;
                for (int k = 0; k < 6; k++) if (n[k] > n[best]) best = k;
                c[p] = best;
            }
        return m;
    }

    static bool[] FloorMedian(bool[] m, int w, int h, int half, int depth, int rows) {
        var o = (bool[])m.Clone();
        var floor = new bool[w * h];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++) {
                int p = y * w + x;
                if (!m[p] || (y > 0 && m[p - w])) continue;
                bool below = true;
                for (int k = 1; k <= depth && below; k++) below = y + k >= h || m[p + k * w];
                floor[p] = below;
            }
        var hs = new List<int>();
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++) {
                if (!floor[y * w + x]) continue;
                hs.Clear();
                for (int d = -half; d <= half; d++) {
                    int cx = x + d, best = -1;
                    if (cx < 0 || cx >= w) continue;
                    for (int j = Math.Max(0, y - rows); j <= Math.Min(h - 1, y + rows); j++)
                        if (floor[j * w + cx] && (best < 0 || Math.Abs(j - y) < Math.Abs(best - y))) best = j;
                    if (best >= 0) hs.Add(best);
                }
                if (hs.Count < half + 1) continue;
                hs.Sort();
                int t = hs.Count % 2 == 1 ? hs[hs.Count / 2] : (hs[hs.Count / 2 - 1] + hs[hs.Count / 2]) / 2;
                for (int j = t; j < y; j++) o[j * w + x] = true;
                for (int j = y; j < t; j++) o[j * w + x] = false;
            }
        return o;
    }

    static bool InDisk(int dx, int dy, int r) { return dx * dx + dy * dy <= r * r + r; }

    static bool[] Dilate(bool[] m, int w, int h, int r) {
        var o = new bool[w * h];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++) {
                bool v = false;
                for (int dy = -r; dy <= r && !v; dy++)
                    for (int dx = -r; dx <= r && !v; dx++) {
                        int j = y + dy, i = Math.Min(w - 1, Math.Max(0, x + dx));
                        v = InDisk(dx, dy, r) && j >= 0 && j < h && m[j * w + i];
                    }
                o[y * w + x] = v;
            }
        return o;
    }

    static bool[] Erode(bool[] m, int w, int h, int r) {
        var o = new bool[w * h];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++) {
                bool v = true;
                for (int dy = -r; dy <= r && v; dy++)
                    for (int dx = -r; dx <= r && v; dx++) {
                        if (!InDisk(dx, dy, r)) continue;
                        int j = y + dy, i = Math.Min(w - 1, Math.Max(0, x + dx));
                        bool s = j >= h || (j >= 0 && m[j * w + i]);
                        v = s;
                    }
                o[y * w + x] = v;
            }
        return o;
    }

    public static int[] Colour(int[] c) {
        var o = new int[c.Length];
        for (int i = 0; i < c.Length; i++) o[i] = unchecked((int)0xFF000000) | Preview[c[i]];
        return o;
    }

    // Opens a flight corridor from (sx, sy) to (gx, gy): the path of disk centres (radius r)
    // that removes the fewest solid pixels, each step costing 1 + penalty * (solid pixels
    // in the disk). The world's left, right and bottom edges count as solid; above the map
    // is open. Solid pixels inside any disk on the path become the class of the nearest
    // open pixel (sky or cave background). Returns the number of pixels opened.
    public static int CarveRoute(int[] c, int w, int h, int sx, int sy, int gx, int gy, int r, double penalty) {
        Func<int, int, bool> solidAt = (x, y) =>
            y < 0 ? false : (x < 0 || x >= w || y >= h) ? true : c[y * w + x] >= ROCK && c[y * w + x] <= DARK;
        var cost = new double[w * h];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++) {
                int n = 0;
                for (int dy = -r; dy <= r; dy++)
                    for (int dx = -r; dx <= r; dx++)
                        if (dx * dx + dy * dy <= r * r && solidAt(x + dx, y + dy)) n++;
                cost[y * w + x] = 1 + penalty * n;
            }
        var dist = new double[w * h];
        var from = new int[w * h];
        for (int i = 0; i < w * h; i++) { dist[i] = double.MaxValue; from[i] = -1; }
        var heap = new List<KeyValuePair<double, int>>();
        int start = sy * w + sx, goal = gy * w + gx;
        dist[start] = 0; HeapPush(heap, 0, start);
        while (heap.Count > 0) {
            var top = HeapPop(heap);
            int p = top.Value;
            if (top.Key > dist[p]) continue;
            if (p == goal) break;
            int x = p % w, y = p / w;
            for (int dy = -1; dy <= 1; dy++)
                for (int dx = -1; dx <= 1; dx++) {
                    int nx = x + dx, ny = y + dy;
                    if ((dx == 0 && dy == 0) || nx < 0 || nx >= w || ny < 0 || ny >= h) continue;
                    int q = ny * w + nx;
                    double d = dist[p] + (dx != 0 && dy != 0 ? 1.4142 : 1.0) * cost[q];
                    if (d < dist[q]) { dist[q] = d; from[q] = p; HeapPush(heap, d, q); }
                }
        }
        if (from[goal] < 0) throw new Exception("No route between the corridor ends");
        var carve = new bool[w * h];
        for (int p = goal; p >= 0; p = p == start ? -1 : from[p]) {
            int x = p % w, y = p / w;
            for (int dy = -r; dy <= r; dy++)
                for (int dx = -r; dx <= r; dx++) {
                    int i = x + dx, j = y + dy;
                    if (dx * dx + dy * dy <= r * r && i >= 0 && i < w && j >= 0 && j < h && solidAt(i, j)) carve[j * w + i] = true;
                }
        }
        var queue = new Queue<int>();
        for (int i = 0; i < w * h; i++) if (!carve[i] && c[i] < ROCK) queue.Enqueue(i);
        int opened = 0;
        while (queue.Count > 0) {
            int p = queue.Dequeue(), x = p % w, y = p / w;
            foreach (var q in new[] { x > 0 ? p - 1 : -1, x < w - 1 ? p + 1 : -1, y > 0 ? p - w : -1, y < h - 1 ? p + w : -1 })
                if (q >= 0 && carve[q]) { carve[q] = false; c[q] = c[p]; opened++; queue.Enqueue(q); }
        }
        return opened;
    }

    static void HeapPush(List<KeyValuePair<double, int>> heap, double key, int value) {
        heap.Add(new KeyValuePair<double, int>(key, value));
        for (int i = heap.Count - 1; i > 0; ) {
            int parent = (i - 1) / 2;
            if (heap[parent].Key <= heap[i].Key) break;
            var t = heap[parent]; heap[parent] = heap[i]; heap[i] = t; i = parent;
        }
    }

    static KeyValuePair<double, int> HeapPop(List<KeyValuePair<double, int>> heap) {
        var top = heap[0];
        heap[0] = heap[heap.Count - 1]; heap.RemoveAt(heap.Count - 1);
        for (int i = 0; ; ) {
            int l = 2 * i + 1, rt = l + 1, m = i;
            if (l < heap.Count && heap[l].Key < heap[m].Key) m = l;
            if (rt < heap.Count && heap[rt].Key < heap[m].Key) m = rt;
            if (m == i) break;
            var t = heap[m]; heap[m] = heap[i]; heap[i] = t; i = m;
        }
        return top;
    }

    // Textured preview with right_renderer's colours, one output pixel per world pixel.
    // A map pixel covers scale by scale world pixels; at scale 2 each quarter follows
    // level_map's Scale2x edge smoothing. Texture units are half world pixels, as on the
    // board. The moon (texture-unit centre, negative to omit) shows through sky only, and
    // the finish flag is drawn at its world top-left.
    public static int[] Render(int[] c, int w, int h, int scale, int moonX, int moonY, int flagX, int flagY) {
        int ow = w * scale, oh = h * scale;
        var o = new int[ow * oh];
        Func<int, int, int> at = (x, y) => (x < 0 || x >= w || y < 0) ? SKY : y >= h ? DARK : c[y * w + x];
        for (int wy = 0; wy < oh; wy++)
            for (int wx = 0; wx < ow; wx++) {
                int mx = wx / scale, my = wy / scale, k = at(mx, my);
                if (scale == 2) {
                    int n = at(mx, my - 1), s = at(mx, my + 1), we = at(mx - 1, my), e = at(mx + 1, my);
                    bool right = (wx & 1) == 1, down = (wy & 1) == 1;
                    if (!down && !right && we == n && n != e && we != s) k = n;
                    if (!down && right && n == e && n != we && e != s) k = e;
                    if (down && !right && we == s && we != n && s != e) k = we;
                    if (down && right && s == e && e != n && s != we) k = e;
                }
                int tx = 2 * wx, ty = 2 * wy, rgb;
                switch (k) {
                    case CAVE: rgb = Stone(tx, ty, 0x08a2, 0x2a88, 0x1985, 0x21c6, 0x2227); break;
                    case ROCK: rgb = Stone(tx, ty, 0x1988, 0x6c97, 0x3af0, 0x4352, 0x4bd4); break;
                    case GRASS: rgb = 0x4d86; break;
                    case ROAD: rgb = ((tx * 3 ^ ty * 5) & 7) == 0 ? 0x4a89 : 0x3a28; break;
                    case DARK: rgb = 0x1082; break;
                    default:
                        rgb = new[] { 0x322d, 0x3a8f, 0x4af1, 0x5b94, 0x6c57, 0x8d1a, 0xa5fd }[Math.Min(6, ty >> 6)];
                        int dx = tx - moonX, dy = ty - moonY;
                        if (moonX >= 0 && dx * dx + dy * dy <= 324) rgb = dx * dx + (dy + 6) * (dy + 6) <= 16 ? 0xc65a : 0xe75e;
                        break;
                }
                int fx = tx - 2 * flagX, fy = ty - 2 * flagY;
                if (fx >= 0 && fx < 3 && fy >= 0 && fy < 28) rgb = fx == 0 ? 0xfd8c : fx == 1 ? 0xec05 : 0xaa82;
                else if (fx >= 3 && fx < 23 && fy >= 1 && fy < 17)
                    rgb = (fx == 3 || fx == 22 || fy == 1 || fy == 16) ? 0x3186 : ((((fx - 3) >> 2) ^ ((fy - 1) >> 2)) & 1) == 1 ? 0x0000 : 0xffff;
                o[wy * ow + wx] = unchecked((int)0xFF000000) | (((rgb >> 11) & 31) * 255 / 31) << 16 | (((rgb >> 5) & 63) * 255 / 63) << 8 | (rgb & 31) * 255 / 31;
            }
        return o;
    }

    // right_renderer's staggered stones: mortar, a lit top-left edge and three shades.
    static int Stone(int fx, int fy, int mortar, int light, int a, int b, int c) {
        int row = fy >> 3, shifted = fx + ((row * 5) & 15), lx = shifted & 15, ly = fy & 7;
        int shade = ((shifted >> 4) ^ (row << 1) ^ (shifted >> 6) ^ row) & 3;
        if (lx == 0 || ly == 0 || (lx == 1 && ly == 1)) return mortar;
        if (lx == 1 || ly == 1) return light;
        return shade == 0 ? a : shade == 2 ? c : b;
    }
}
