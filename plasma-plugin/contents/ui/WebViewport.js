.pragma library

function compute(outputWidth, outputHeight, mode, referenceWidth, referenceHeight) {
    const outWidth = Number(outputWidth)
    const outHeight = Number(outputHeight)
    const refWidth = Number(referenceWidth)
    const refHeight = Number(referenceHeight)
    if (!isFinite(outWidth) || !isFinite(outHeight) || !isFinite(refWidth) || !isFinite(refHeight)
            || outWidth <= 0 || outHeight <= 0 || refWidth <= 0 || refHeight <= 0) {
        return {
            x: 0,
            y: 0,
            width: 1,
            height: 1,
            renderWidth: 1,
            renderHeight: 1,
            scaleX: 1,
            scaleY: 1,
            verticalTransform: 1
        }
    }

    const normalizedMode = String(mode || "fill").toLowerCase()
    let scaleX
    let scaleY
    if (normalizedMode === "stretch") {
        scaleX = outWidth / refWidth
        scaleY = outHeight / refHeight
    } else {
        const uniform = normalizedMode === "fit"
                ? Math.min(outWidth / refWidth, outHeight / refHeight)
                : Math.max(outWidth / refWidth, outHeight / refHeight)
        scaleX = uniform
        scaleY = uniform
    }

    const width = refWidth * scaleX
    const height = refHeight * scaleY
    return {
        x: (outWidth - width) / 2,
        y: (outHeight - height) / 2,
        width: width,
        height: height,
        renderWidth: refWidth * scaleX,
        renderHeight: refHeight * scaleX,
        scaleX: scaleX,
        scaleY: scaleY,
        verticalTransform: scaleY / scaleX
    }
}
