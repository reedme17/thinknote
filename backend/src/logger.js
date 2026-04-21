export function createLogger() {
    return {
        info(event, data = {}) {
            write("INFO", event, data);
        },
        warn(event, data = {}) {
            write("WARN", event, data);
        },
        error(event, data = {}) {
            write("ERROR", event, data);
        }
    };
}

function write(level, event, data) {
    const payload = {
        timestamp: new Date().toISOString(),
        level,
        event,
        ...sanitize(data)
    };

    const message = JSON.stringify(payload);
    if (level === "ERROR") {
        console.error(message);
        return;
    }

    console.log(message);
}

function sanitize(data) {
    const clone = { ...data };

    for (const [key, value] of Object.entries(clone)) {
        if (!value || typeof value !== "object") {
            continue;
        }

        if (key.toLowerCase().includes("note") || key.toLowerCase().includes("message")) {
            clone[key] = summarizeObject(value);
        }
    }

    return clone;
}

function summarizeObject(value) {
    if (typeof value === "string") {
        return { preview: value.slice(0, 120), length: value.length };
    }

    if (Array.isArray(value)) {
        return { count: value.length };
    }

    const next = {};
    for (const [key, child] of Object.entries(value)) {
        if (typeof child === "string") {
            next[key] = { preview: child.slice(0, 120), length: child.length };
        } else if (Array.isArray(child)) {
            next[key] = { count: child.length };
        } else {
            next[key] = child;
        }
    }
    return next;
}
