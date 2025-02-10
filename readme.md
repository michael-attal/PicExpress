# **PicExpress : Polygon Clipping & Filling (Math Project)**

This application demonstrates polygon **clipping** (Cyrus-Beck, Sutherland-Hodgman, and concave-window clipping via ear clipping) and **filling** (seed-fill, scanline, LCA) in Swift 6 using Metal and SwiftUI.

It was originally developed as a **Math course project** on geometric algorithms.

**Features**

• **Multiple Polygons**: Load/store several polygons (convex, concave, or self-intersecting).

• **Window Clipping**:

• **Convex window**: Use Cyrus-Beck or Sutherland-Hodgman.

• **Concave window**: Decompose via ear clipping, then apply the chosen algorithm.

• **Polygon Filling**:

• **Seed-Fill** (recursive or stack-based).

• **Scanline**.

• **LCA** (Active Edge Table).

• **Eraser, resizing, pre-shaping**... tools.

• **Modern SwiftUI/Metal Interface**:

• Pan & Zoom.

• Tool panel to select the clipping/filling algorithm.

• Real-time rendering with a single click or keyboard validation to trigger each algorithm.

**Usage**

1. **Open** the app and select or create a new document (which contains polygons).
2. **Draw** a polygon.
3. **Choose** a clipping or filling algorithm in the side panel.
4. **Apply** the operation (e.g., draw or adjust a window polygon, then press Enter) to see the resulting clipped/filled shape.
5. **Pan/Zoom** to inspect details.

That’s it! You can experiment with different polygons, windows, and filling techniques.

