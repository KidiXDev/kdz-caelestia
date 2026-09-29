pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Caelestia
import Caelestia.I18n
import qs.services
import qs.utils

// Staged monitor configuration for the Display page. Edits are kept in `pending` and only reach Hyprland through
// apply(), which then waits for keep() or reverts on its own once the countdown runs out.
Singleton {
    id: root

    // Long enough to check whether the new mode works, short enough that a black screen isn't a disaster
    readonly property int confirmTimeout: 15

    readonly property bool usingLua: Hypr.usingLua
    readonly property var monitors: Hypr.extras.monitors
    readonly property var layout: layoutRects(pending)

    property var pending: ({})
    readonly property bool hasChanges: Object.keys(pending).length > 0

    property bool applying
    property bool confirming
    property int secondsLeft
    property bool identifying
    property var appliedRules: []
    property var revertRules: []

    readonly property string userFile: `${Paths.config}/hypr-user.${usingLua ? "lua" : "conf"}`
    readonly property string managedFile: `${Paths.config}/hypr-monitors.${usingLua ? "lua" : "conf"}`
    property bool userFileExists
    property bool hasInclude
    property var userRules: []
    property var managedRules: []
    readonly property bool includeMissing: managedRules.length > 0 && !hasInclude

    function monitor(name: string): var {
        return monitors.find(m => m.name === name) ?? null;
    }

    function displayName(mon: var): string {
        return [mon?.make, mon?.model].filter(s => s && s !== "Unknown").join(" ") || (mon?.name ?? "");
    }

    function isMirroring(mon: var): bool {
        const target = String(mon?.mirrorOf ?? "none");
        return target !== "none" && target !== "";
    }

    // mirrorOf is the id of the mirrored output, not its name
    function mirrorName(mon: var): string {
        const target = String(mon?.mirrorOf ?? "");
        return monitors.find(m => String(m.id) === target || m.name === target)?.name ?? target;
    }

    // Labels

    function resolutionLabel(width: int, height: int): string {
        // TRANSLATORS: display resolution, %1 = width, %2 = height
        return Tr.tr("%1 × %2").arg(width).arg(height);
    }

    function rateLabel(rate: real): string {
        // TRANSLATORS: refresh rate, %1 = a number
        return Tr.tr("%1 Hz").arg(formatRate(rate));
    }

    function scaleLabel(scale: real): string {
        // TRANSLATORS: %1 = a number
        return Tr.tr("%1%").arg(Math.round(scale * 1000) / 10);
    }

    function transformLabel(transform: int): string {
        return [Tr.trCtx("Normal", "display rotation"), Tr.trCtx("90°", "display rotation"), Tr.trCtx("180°", "display rotation"), Tr.trCtx("270°", "display rotation"), Tr.trCtx("Flipped", "display rotation"), Tr.trCtx("Flipped, 90°", "display rotation"), Tr.trCtx("Flipped, 180°", "display rotation"), Tr.trCtx("Flipped, 270°", "display rotation")][transform] ?? String(transform);
    }

    function summary(name: string): string {
        const mon = monitor(name);
        const st = state(name);
        if (!mon || !st)
            return "";
        if (st.disabled)
            return Tr.trCtx("Disabled", "display");
        if (isMirroring(mon))
            return Tr.tr("Mirroring %1").arg(mirrorName(mon));
        return [resolutionLabel(st.width, st.height), rateLabel(st.rate), scaleLabel(st.scale)].join(" · ");
    }

    // The rule Hyprland currently uses for this output. Nexus rules load after hypr-user, so they win on ties.
    function ruleFor(mon: var): var {
        return MonitorRules.find(userRules.concat(managedRules), mon);
    }

    // Only counts saved rules once Hyprland actually loads them
    function ruleSource(mon: var): string {
        const rule = MonitorRules.find(hasInclude ? userRules.concat(managedRules) : userRules, mon);
        if (!rule)
            return Tr.trCtx("Default", "monitor rule source");
        return managedRules.includes(rule) ? Paths.shortenHome(managedFile) : Paths.shortenHome(userFile);
    }

    // Modes

    function roundRate(rate: real): real {
        return Math.round(rate * 100) / 100;
    }

    function modes(mon: var): var {
        const out = {};
        for (const mode of mon?.availableModes ?? []) {
            const match = /^(\d+)x(\d+)@([\d.]+)Hz$/.exec(mode);
            if (!match)
                continue;
            const key = `${match[1]}x${match[2]}`;
            const rate = roundRate(parseFloat(match[3]));
            if (!out[key])
                out[key] = [];
            if (!out[key].includes(rate))
                out[key].push(rate);
        }

        // Some drivers report no modes, so at least offer the current one
        if (mon?.width > 0 && mon.refreshRate > 0) {
            const key = `${mon.width}x${mon.height}`;
            const rate = roundRate(mon.refreshRate);
            if (!out[key])
                out[key] = [];
            if (!out[key].includes(rate))
                out[key].push(rate);
        }

        for (const key of Object.keys(out))
            out[key].sort((a, b) => b - a);
        return out;
    }

    function resolutions(mon: var): var {
        return Object.keys(modes(mon)).map(k => {
            const [width, height] = k.split("x").map(Number);
            return {
                width: width,
                height: height
            };
        }).sort((a, b) => b.width * b.height - a.width * a.height || b.width - a.width);
    }

    function rates(mon: var, width: int, height: int): var {
        return modes(mon)[`${width}x${height}`] ?? [];
    }

    function nearestRate(mon: var, width: int, height: int, preferred: real): real {
        const available = rates(mon, width, height);
        if (available.length === 0)
            return preferred;
        return available.reduce((best, r) => Math.abs(r - preferred) < Math.abs(best - preferred) ? r : best);
    }

    // Hyprland wants a multiple of 1/120 which divides both dimensions cleanly, anything else gets adjusted
    function validScales(width: int, height: int): var {
        const scales = [];
        if (width <= 0 || height <= 0)
            return [1];
        for (let n = 60; n <= 480; n++)
            if ((width * 120) % n === 0 && (height * 120) % n === 0)
                scales.push(n / 120);
        return scales;
    }

    // Scales worth offering: 100% and up, plus the current one if it's something unusual
    function scaleOptions(st: var): var {
        const scales = validScales(st.width, st.height).filter(s => s >= 1);
        if (!scales.some(s => sameValue("scale", s, st.scale)))
            scales.push(st.scale);
        return scales.sort((a, b) => a - b);
    }

    function nearestScale(scale: real, width: int, height: int): real {
        const scales = validScales(width, height);
        return scales.reduce((best, s) => Math.abs(s - scale) < Math.abs(best - scale) ? s : best, scales[0] ?? 1);
    }

    // State

    function liveState(mon: var): var {
        return {
            width: mon.width,
            height: mon.height,
            rate: roundRate(mon.refreshRate),
            scale: mon.scale,
            transform: mon.transform,
            x: mon.x,
            y: mon.y,
            disabled: mon.disabled
        };
    }

    function state(name: string): var {
        return stateWith(name, pending);
    }

    function stateWith(name: string, pend: var): var {
        const mon = monitor(name);
        if (!mon)
            return null;
        return Object.assign(liveState(mon), pend[name] ?? {});
    }

    function sameValue(key: string, a: var, b: var): bool {
        if (key === "scale" || key === "rate")
            return Math.abs(a - b) < 0.001;
        return a === b;
    }

    // Merges { name: patch } into a pending map, dropping anything equal to the live state
    function mergePending(pend: var, changes: var): var {
        const out = Object.assign({}, pend);
        for (const name of Object.keys(changes)) {
            const mon = monitor(name);
            if (!mon)
                continue;
            const live = liveState(mon);
            const next = Object.assign({}, out[name] ?? {}, changes[name]);
            for (const key of Object.keys(next))
                if (sameValue(key, next[key], live[key]))
                    delete next[key];
            if (Object.keys(next).length > 0)
                out[name] = next;
            else
                delete out[name];
        }
        return out;
    }

    // Drops changes which are now live (or for outputs which are gone)
    function prunePending(): void {
        const changes = {};
        for (const name of Object.keys(pending))
            if (monitor(name))
                changes[name] = pending[name];
        const next = mergePending({}, changes);
        if (JSON.stringify(next) !== JSON.stringify(pending))
            pending = next;
    }

    // Layout

    function logicalSize(st: var): var {
        const swap = st.transform % 2 === 1;
        const scale = st.scale > 0 ? st.scale : 1;
        return {
            w: Math.round((swap ? st.height : st.width) / scale),
            h: Math.round((swap ? st.width : st.height) / scale)
        };
    }

    // Outputs that take up space in the layout (enabled and not mirroring another)
    function layoutRects(pend: var): var {
        const rects = [];
        for (const mon of monitors) {
            if (isMirroring(mon))
                continue;
            const st = stateWith(mon.name, pend);
            if (st.disabled || st.width <= 0)
                continue;
            const size = logicalSize(st);
            rects.push({
                name: mon.name,
                x: st.x,
                y: st.y,
                w: size.w,
                h: size.h
            });
        }
        return rects;
    }

    function overlaps(a: var, b: var): bool {
        return a.x < b.x + b.w && a.x + a.w > b.x && a.y < b.y + b.h && a.y + a.h > b.y;
    }

    function spansOverlap(aStart: int, aSize: int, bStart: int, bSize: int): bool {
        return aStart < bStart + bSize && aStart + aSize > bStart;
    }

    function touches(a: var, b: var): bool {
        const sideBySide = (a.x + a.w === b.x || b.x + b.w === a.x) && spansOverlap(a.y, a.h, b.y, b.h);
        const stacked = (a.y + a.h === b.y || b.y + b.h === a.y) && spansOverlap(a.x, a.w, b.x, b.w);
        return sideBySide || stacked;
    }

    function distance(a: var, b: var): real {
        const dx = Math.max(0, a.x - (b.x + b.w), b.x - (a.x + a.w));
        const dy = Math.max(0, a.y - (b.y + b.h), b.y - (a.y + a.h));
        return Math.hypot(dx, dy);
    }

    // Closest spot to (x, y) flush against the edge of another output, without overlapping any of them
    function snap(rect: var, others: var, x: int, y: int): var {
        if (others.length === 0)
            return {
                x: 0,
                y: 0
            };

        const threshold = Math.round(Math.max(rect.w, rect.h) * 0.05);
        // Slide along the edge while keeping the shorter edge fully in contact, sticking to start/centre/end
        const along = (pos, start, size, otherSize) => {
            const lo = Math.min(start, start + otherSize - size);
            const hi = Math.max(start, start + otherSize - size);
            const clamped = Math.max(lo, Math.min(hi, pos));
            for (const align of [start, start + Math.round((otherSize - size) / 2), start + otherSize - size])
                if (Math.abs(clamped - align) <= threshold)
                    return align;
            return clamped;
        };

        let best = null;
        let bestDist = Infinity;
        for (const o of others) {
            const cx = along(x, o.x, rect.w, o.w);
            const cy = along(y, o.y, rect.h, o.h);
            const candidates = [[o.x - rect.w, cy], [o.x + o.w, cy], [cx, o.y - rect.h], [cx, o.y + o.h]];
            for (const [px, py] of candidates) {
                const moved = {
                    x: px,
                    y: py,
                    w: rect.w,
                    h: rect.h
                };
                if (others.some(r => overlaps(moved, r)))
                    continue;
                const dist = Math.hypot(px - x, py - y);
                if (dist < bestDist) {
                    best = {
                        x: px,
                        y: py
                    };
                    bestDist = dist;
                }
            }
        }
        return best;
    }

    // Moves the outputs attached to the right/bottom edge of `from` (and the ones attached to those) by dx/dy
    function shiftAttached(rects: var, from: var, dx: int, dy: int, visited: var): void {
        for (const r of rects) {
            if (visited.includes(r.name))
                continue;
            const right = dx !== 0 && r.x === from.x + from.w && spansOverlap(r.y, r.h, from.y, from.h);
            const below = dy !== 0 && r.y === from.y + from.h && spansOverlap(r.x, r.w, from.x, from.w);
            if (!right && !below)
                continue;
            visited.push(r.name);
            const old = Object.assign({}, r);
            if (right)
                r.x += dx;
            if (below)
                r.y += dy;
            shiftAttached(rects, old, right ? dx : 0, below ? dy : 0, visited);
        }
    }

    // Grows a group from the anchor, pulling anything overlapping or detached from it onto the nearest free edge,
    // so the layout ends up in one piece without overlaps
    function resolveLayout(rects: var, anchor: var): void {
        const group = [anchor];
        const rest = rects.filter(r => r !== anchor);

        while (rest.length > 0) {
            let idx = rest.findIndex(r => !group.some(g => overlaps(r, g)) && group.some(g => touches(r, g)));
            if (idx < 0) {
                const gap = r => Math.min(...group.map(g => distance(r, g)));
                idx = rest.reduce((best, r, i) => gap(r) < gap(rest[best]) ? i : best, 0);
                const rect = rest[idx];
                const pos = snap(rect, group, rect.x, rect.y);
                if (pos) {
                    rect.x = pos.x;
                    rect.y = pos.y;
                }
            }
            group.push(rest.splice(idx, 1)[0]);
        }
    }

    // Commits positions to pending, shifted so the layout starts at 0x0
    function withPositions(pend: var, rects: var): var {
        if (rects.length === 0)
            return pend;
        const minX = Math.min(...rects.map(r => r.x));
        const minY = Math.min(...rects.map(r => r.y));
        const changes = {};
        for (const r of rects)
            changes[r.name] = {
                x: r.x - minX,
                y: r.y - minY
            };
        return mergePending(pend, changes);
    }

    // Stages a change to an output, keeping the rest of the layout attached and free of overlaps
    function stage(name: string, patch: var): void {
        const next = mergePending(pending, {
            [name]: patch
        });
        const old = layoutRects(pending).find(r => r.name === name);
        const rects = layoutRects(next);
        const idx = rects.findIndex(r => r.name === name);

        if (old && idx >= 0) {
            const cur = rects[idx];
            cur.x = old.x;
            cur.y = old.y;
            shiftAttached(rects, old, cur.w - old.w, cur.h - old.h, [name]);
        } else if (old) {
            // Disabled, so close the gap it leaves behind
            shiftAttached(rects, old, -old.w, -old.h, [name]);
        } else if (idx >= 0) {
            // Enabled, so start off to the right of everything else
            const others = rects.filter((_, i) => i !== idx);
            rects[idx].x = others.length > 0 ? Math.max(...others.map(r => r.x + r.w)) : 0;
            rects[idx].y = others.length > 0 ? Math.min(...others.map(r => r.y)) : 0;
        }

        if (rects.length > 0)
            resolveLayout(rects, idx >= 0 ? rects[idx] : rects[0]);
        pending = withPositions(next, rects);
    }

    function setMode(name: string, width: int, height: int, rate: real): void {
        const st = state(name);
        if (!st)
            return;
        const scale = validScales(width, height).some(s => sameValue("scale", s, st.scale)) ? st.scale : nearestScale(st.scale, width, height);
        stage(name, {
            width: width,
            height: height,
            rate: rate,
            scale: scale
        });
    }

    function setScale(name: string, scale: real): void {
        stage(name, {
            scale: scale
        });
    }

    function setTransform(name: string, transform: int): void {
        stage(name, {
            transform: transform
        });
    }

    function canDisable(name: string): bool {
        return layout.some(r => r.name !== name);
    }

    function setDisabled(name: string, disabled: bool): void {
        const mon = monitor(name);
        if (!mon || (disabled && !canDisable(name)))
            return;

        const patch = {
            disabled: disabled
        };
        // Disabled outputs might not report a mode, so fall back to the best one available
        const st = state(name);
        if (!disabled && (st.width <= 0 || st.rate <= 0)) {
            const res = st.width > 0 ? st : resolutions(mon)[0];
            if (res) {
                patch.width = res.width;
                patch.height = res.height;
                patch.rate = rates(mon, res.width, res.height)[0] ?? 60;
                patch.scale = st.scale > 0 ? nearestScale(st.scale, res.width, res.height) : 1;
            }
        }
        stage(name, patch);
    }

    function setPosition(name: string, x: int, y: int): void {
        const rects = layoutRects(pending);
        const rect = rects.find(r => r.name === name);
        if (!rect)
            return;

        const pos = snap(rect, rects.filter(r => r !== rect), x, y);
        if (pos) {
            rect.x = pos.x;
            rect.y = pos.y;
        }
        resolveLayout(rects, rect);
        pending = withPositions(pending, rects);
    }

    function discard(): void {
        pending = {};
    }

    // Rules

    function formatRate(rate: real): string {
        return String(roundRate(rate));
    }

    // Keeps whatever the existing rule has (vrr, bitdepth, cm, ...) and the same output identifier, so the new rule
    // replaces it instead of piling up. Fields the user didn't touch keep their original value (e.g. "preferred").
    function buildRule(mon: var, st: var, changed: var): var {
        const base = ruleFor(mon) ?? {
            output: mon.name,
            fields: []
        };
        const values = {
            disabled: st.disabled
        };

        if (!st.disabled) {
            const want = (key, keys) => keys.some(k => changed.includes(k)) || !MonitorRules.field(base, key);
            if (want("mode", ["width", "height", "rate"]))
                values.mode = `${st.width}x${st.height}@${formatRate(st.rate)}`;
            if (want("position", ["x", "y"]))
                values.position = `${st.x}x${st.y}`;
            if (want("scale", ["scale"]))
                values.scale = st.scale;
            if (want("transform", ["transform"]))
                values.transform = st.transform;
        }

        return MonitorRules.withFields(base, values, usingLua);
    }

    function isDisableRule(rule: var): bool {
        return MonitorRules.value(rule, "disabled") === true;
    }

    // Enable/change first and disable last, so there's never a moment without any output
    function sendRules(rules: var, callback: var): void {
        const sorted = [...rules].sort((a, b) => Number(isDisableRule(a)) - Number(isDisableRule(b)));
        Hypr.extras.batchMessage(sorted.map(r => MonitorRules.command(r, usingLua)), (ok, reply) => {
            refreshTimer.restart();
            Hypr.extras.refreshMonitors();
            Hyprland.refreshMonitors();
            // Each command in a batch replies "ok" or an error, separated by blank lines
            const errors = reply.split("\n\n\n").map(r => r.trim()).filter(r => r && r !== "ok");
            if (callback)
                callback(ok && errors.length === 0, errors.join("\n"));
        });
    }

    function apply(): void {
        if (!hasChanges || applying || confirming)
            return;

        const applied = [];
        const reverts = [];
        for (const name of Object.keys(pending)) {
            const mon = monitor(name);
            if (!mon)
                continue;
            applied.push(buildRule(mon, state(name), Object.keys(pending[name])));
            reverts.push(buildRule(mon, liveState(mon), ["width", "height", "rate", "x", "y", "scale", "transform"]));
        }

        // Everything pending was for outputs which are gone now
        if (applied.length === 0) {
            pending = {};
            return;
        }

        applying = true;
        appliedRules = applied;
        revertRules = reverts;
        sendRules(applied, (ok, error) => {
            applying = false;
            if (!ok) {
                sendRules(revertRules, null);
                clearSession();
                Toaster.toast(Tr.tr("Unable to apply display settings"), error || Tr.tr("Hyprland rejected the new configuration"), "error", Toast.Error);
                return;
            }

            secondsLeft = confirmTimeout;
            confirming = true;
            countdown.restart();
        });
    }

    function revert(): void {
        if (!confirming)
            return;

        countdown.stop();
        sendRules(revertRules, (ok, error) => {
            if (!ok)
                Toaster.toast(Tr.tr("Unable to revert display settings"), error, "error", Toast.Error);
        });
        clearSession();
        pending = {};
        Toaster.toast(Tr.tr("Display settings reverted"), Tr.tr("Your previous display settings have been restored"), "settings_backup_restore");
    }

    function keep(): void {
        if (!confirming)
            return;

        countdown.stop();

        // Replace rules for the same output, keep everything else (e.g. outputs that aren't plugged in right now)
        const rules = [...managedRules];
        for (const rule of appliedRules) {
            const idx = rules.findIndex(r => r.output === rule.output);
            if (idx >= 0)
                rules[idx] = rule;
            else
                rules.push(rule);
        }
        managedRules = rules;
        managedView.setText(MonitorRules.serialize(rules, usingLua));

        clearSession();
        pending = {};

        if (hasInclude)
            Toaster.toast(Tr.tr("Display settings saved"), Tr.tr("Saved to %1").arg(Paths.shortenHome(managedFile)), "monitor", Toast.Success);
        else
            Toaster.toast(Tr.tr("Display settings applied"), Tr.tr("Add the include from the Display page so they persist after Hyprland reloads"), "monitor", Toast.Warning);
    }

    function clearSession(): void {
        confirming = false;
        appliedRules = [];
        revertRules = [];
    }

    function addInclude(): void {
        if (!userFileExists || hasInclude)
            return;

        const text = userView.text();
        const sep = text.length === 0 || text.endsWith("\n") ? "" : "\n";
        userView.setText(text + sep + MonitorRules.includeSnippet(usingLua, Paths.shortenHome(managedFile)));
        hasInclude = true;
    }

    function identify(): void {
        identifying = true;
        identifyTimer.restart();
    }

    onMonitorsChanged: prunePending()

    Timer {
        id: countdown

        interval: 1000
        repeat: true
        onTriggered: {
            root.secondsLeft--;
            if (root.secondsLeft <= 0)
                root.revert();
        }
    }

    Timer {
        id: identifyTimer

        interval: 3000
        onTriggered: root.identifying = false
    }

    // Outputs can take a moment to settle after a mode change, so check again once they have
    Timer {
        id: refreshTimer

        interval: 1000
        onTriggered: {
            Hypr.extras.refreshMonitors();
            Hyprland.refreshMonitors();
        }
    }

    FileView {
        id: userView

        path: root.userFile
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.userFileExists = true;
            root.userRules = MonitorRules.parse(text(), root.usingLua);
            root.hasInclude = MonitorRules.hasInclude(text(), root.usingLua);
        }
        onLoadFailed: {
            root.userFileExists = false;
            root.userRules = [];
            root.hasInclude = false;
        }
    }

    FileView {
        id: managedView

        path: root.managedFile
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.managedRules = MonitorRules.parse(text(), root.usingLua)
        onLoadFailed: root.managedRules = []
    }
}
