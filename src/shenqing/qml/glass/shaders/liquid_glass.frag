#version 440

// 液态玻璃（Liquid Glass）片段着色器
// 改造自 CW2「液态玻璃」主题的 glass.frag：保留圆角透镜折射、边缘色散、
// 镜面高光与自适应 tint，但采样对象换成 App 自己的背景层（ShaderEffectSource），
// 并把磨砂（frost）降为可选的低强度项 —— 用户要的是「清澈玻璃」，不是磨砂白雾。
//
// 关键约束：Qt 6 + D3D11 必须用 qsb --qt6 编译成 .qsb，否则 ShaderEffect 静默不渲染。

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

// QML 属性按声明顺序进入该 uniform block（qt_Matrix / qt_Opacity 恒在最前）
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 size;           // 逻辑尺寸（px）
    float dpr;           // 设备像素比
    float pad;           // 纹理外扩（逻辑 px）：让边缘能采样到卡片外面，避免暗色楔形
    float radius;        // 圆角
    float depth;         // 折射强度 0..2
    float frost;         // 磨砂 0..1（默认很低）
    float aberration;    // 色散 0..2
    float highlight;     // 镜面高光 0..2
    float whiten;        // 白雾 0..0.4
    float tintAlpha;     // tint 混入比例 0..0.6
    float sheen;         // 顶部柔光 0..1
    float hover;         // 悬停/按下强度 0..1
    float sweep;         // 移动高光位置 -0.4..1.4（-1 = 关闭）
    vec2 pointer;        // 指针在控件内的归一化坐标 (0..1)
    float pull;          // 按住形变强度 0..1（0 = 原形）
    vec4 tintColor;      // 玻璃 tint（暗色下用深蓝黑，保证文字对比）
};
layout(binding = 1) uniform sampler2D source;

float roundedBoxSdf(vec2 p, vec2 halfSize, float r) {
    vec2 q = abs(p) - (halfSize - vec2(r));
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

vec3 sampleBackdrop(vec2 uv, vec2 texel) {
    return texture(source, clamp(uv, texel, vec2(1.0) - texel)).rgb;
}

void main() {
    vec2 res = max(size * dpr, vec2(1.0));
    vec2 uv = clamp(qt_TexCoord0, vec2(0.0), vec2(1.0));
    vec2 p = uv * res;
    vec2 halfSize = res * 0.5;
    vec2 center = halfSize;
    float rad = min(radius * dpr, min(halfSize.x, halfSize.y));
    float sdf = roundedBoxSdf(p - center, halfSize, rad);

    // 液态形变：按住不放时，形状朝指针方向鼓起并被拉过去（像捏住一块软玻璃）
    float pullK = clamp(pull, 0.0, 1.0);
    if (pullK > 0.001) {
        vec2 ptrPx = clamp(pointer, vec2(0.0), vec2(1.0)) * res;
        float smallSide = min(halfSize.x, halfSize.y);
        // 整体被指针往那个方向拽一点
        vec2 anchor = vec2(ptrPx.x - center.x, ptrPx.y - center.y);
        sdf = roundedBoxSdf(p - center - anchor * pullK * 0.10, halfSize, rad);
        // 指针附近局部鼓起（高斯）
        vec2 dv = p - ptrPx;
        float sigma = max(rad * 0.85, smallSide * 0.62);
        float gauss = exp(-dot(dv, dv) / (2.0 * sigma * sigma));
        sdf -= pullK * gauss * smallSide * 0.34;
    }

    float aa = 1.0 / max(1.0, dpr);
    float inside = smoothstep(aa, -aa, sdf);
    if (inside <= 0.0005) {
        fragColor = vec4(0.0);
        return;
    }

    // 边缘带：越靠近圆角/边框，折射越强
    float edgeD = max(-sdf, 0.0);
    float band = min(max(8.0 * dpr, (12.0 + 16.0 * depth) * dpr),
                     min(halfSize.x, halfSize.y) * 0.30);
    float t = clamp(edgeD / band, 0.0, 1.0);
    float lens = pow(1.0 - t, 2.0);

    vec2 dir = (p - center) / max(halfSize, vec2(1.0));
    vec2 n = dir / max(length(dir), 1e-4);

    // 纹理 = 卡片区域向外扩 pad，边缘折射才能采到真正的「卡片背后之外」
    float padPx = max(pad, 0.0) * dpr;
    vec2 texRes = res + vec2(2.0 * padPx);
    vec2 texel = 1.0 / max(texRes, vec2(1.0));

    // 卡片像素坐标 -> 纹理像素坐标
    vec2 cardPx = uv * res;
    vec2 texPx = cardPx + vec2(padPx);

    // 透镜位移：玻璃边缘把背后内容「折」进来（像素单位，施加在纹理坐标上）
    float shift = min(lens * (6.0 + 10.0 * depth) * dpr, min(halfSize.x, halfSize.y) * 0.12);
    vec2 samplePx = texPx - n * shift;
    vec2 sampleUv = clamp(samplePx / texRes, texel, vec2(1.0) - texel);

    // 色散：红蓝分离一点，边缘更明显
    float ca = aberration * (0.4 + 1.4 * lens) * dpr;
    vec2 caUv = n * (ca / texRes);

    vec3 col;
    col.r = sampleBackdrop(sampleUv + caUv, texel).r;
    col.g = sampleBackdrop(sampleUv, texel).g;
    col.b = sampleBackdrop(sampleUv - caUv, texel).b;

    // 轻磨砂：只在参数要求时做 4 tap，默认几乎关闭（清澈感优先）
    if (frost > 0.001) {
        float r = frost * (1.4 + 2.0 * lens) * 1.2 * dpr;
        vec2 o = vec2(r) / texRes;
        vec3 acc = col;
        acc += sampleBackdrop(sampleUv + vec2(o.x, 0.0), texel);
        acc += sampleBackdrop(sampleUv - vec2(o.x, 0.0), texel);
        acc += sampleBackdrop(sampleUv + vec2(0.0, o.y), texel);
        acc += sampleBackdrop(sampleUv - vec2(0.0, o.y), texel);
        col = acc / 5.0;
    }

    // 轻微去饱和 + 提对比：玻璃后面的色块不要糊成一片
    float lum = dot(col, vec3(0.2126, 0.7152, 0.0722));
    col = mix(vec3(lum), col, 0.90);
    col = clamp((col - 0.5) * 1.04 + 0.5, 0.0, 1.0);

    // 白雾（极少量即可，太多就是磨砂）
    col = mix(col, vec3(1.0), clamp(whiten, 0.0, 0.4));

    // 玻璃 tint：暗色下压一点亮度，让文字始终可读
    col = mix(col, tintColor.rgb, clamp(tintAlpha, 0.0, 0.6));

    // 顶部柔光
    col += vec3(smoothstep(1.0, 0.0, uv.y) * sheen * 0.10);

    // 镜面高光：左上光源，边缘最强；hover 时整体提亮
    vec2 lightDir = normalize(vec2(-0.5, -0.9));
    float ndl = clamp(dot(n, lightDir), 0.0, 1.0);
    float rim = pow(1.0 - t, 3.5);
    float hov = clamp(hover, 0.0, 1.0);
    col += vec3(rim * (0.25 + 0.75 * ndl) * highlight * (0.55 + 0.75 * hov));

    // 沿玻璃内部对角扫过的高光带（液态流动感）：sweep < 0 时关闭
    if (sweep > -0.4) {
        float u = uv.x * 0.78 + uv.y * 0.62;
        float band = smoothstep(0.22, 0.0, abs(u - sweep));
        float band2 = smoothstep(0.08, 0.0, abs(u - sweep - 0.14));
        col += vec3((band * 0.10 + band2 * 0.06) * (0.45 + 0.9 * hov));
    }

    // 右下边缘轻微压暗：让玻璃有厚度
    col *= 1.0 - 0.16 * rim * (1.0 - ndl);

    // 边缘 1px 高光线：液态玻璃的「壳」
    float line = smoothstep(1.4 * dpr, 0.0, edgeD);
    col = mix(col, vec3(1.0), line * (0.18 + 0.30 * ndl + 0.18 * hov));

    fragColor = vec4(col, 1.0) * inside * qt_Opacity;
}
