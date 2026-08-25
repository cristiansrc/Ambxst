.pragma library

function clone(obj) {
    return JSON.parse(JSON.stringify(obj));
}

function validate(current, defaults, keyName) {
    if (current === undefined || current === null) {
        return clone(defaults);
    }

    if (Array.isArray(defaults)) {
        if (!Array.isArray(current)) {
            return clone(defaults);
        }
        return current;
    }

    if (typeof defaults === 'object') {
        if (typeof current !== 'object' || Array.isArray(current)) {
            return clone(defaults);
        }

        var result = {};
        for (var key in defaults) {
            result[key] = validate(current[key], defaults[key], key);
        }
        return result;
    }

    if (typeof current !== typeof defaults) {
        return defaults;
    }

    if (keyName === "gradientType") {
        var validTypes = ["linear", "radial", "halftone"];
        if (validTypes.indexOf(current) === -1) {
            return defaults;
        }
    }

    if (keyName === "noMediaDisplay") {
        var validMediaOptions = ["userHost", "compositor", "custom"];
        if (validMediaOptions.indexOf(current) === -1) {
            return defaults;
        }
    }

    if (keyName === "perMonitorCount") {
        if (typeof current !== "number" || isNaN(current)) {
            return defaults;
        }
        var clamped = Math.round(current);
        if (clamped < 1) return 1;
        if (clamped > 20) return 20;
        return clamped;
    }

    if (keyName === "shown") {
        if (typeof current !== "number" || isNaN(current)) {
            return defaults;
        }
        var clampedShown = Math.round(current);
        if (clampedShown < 1) return 1;
        if (clampedShown > 20) return 20;
        return clampedShown;
    }

    return current;
}
