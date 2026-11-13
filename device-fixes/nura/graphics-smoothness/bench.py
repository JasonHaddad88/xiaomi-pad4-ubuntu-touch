#!/usr/bin/python3
# Nura UI smoothness bench: a GTK4 list that scrolls itself in short bursts
# with idle gaps, like a finger flick after a pause. Prints frame statistics.
# usage: bench.py [bursts] [label]
import gi, sys, json
gi.require_version('Gtk', '4.0')
from gi.repository import Gtk, GLib

BURSTS = int(sys.argv[1]) if len(sys.argv) > 1 else 12
LABEL = sys.argv[2] if len(sys.argv) > 2 else 'run'
IDLE_MS = 1200          # idle before each burst: long enough for CPU and GPU to ramp down
BURST_US = int(float(sys.argv[3]) * 1e6) if len(sys.argv) > 3 else 700000
SPEED = 2400.0          # px/s
FRAME_US = 16667.0      # 60 Hz


class Bench(Gtk.Application):
    def __init__(self):
        super().__init__(application_id='org.nura.Bench')
        self.bursts = []
        self.direction = 1

    def do_activate(self):
        win = Gtk.ApplicationWindow(application=self, title='Nura bench')
        self.sw = Gtk.ScrolledWindow()
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        icons = ['folder-symbolic', 'document-open-symbolic', 'emblem-system-symbolic',
                 'user-home-symbolic', 'audio-x-generic-symbolic', 'image-x-generic-symbolic']
        for i in range(400):
            row = Gtk.Box(spacing=12)
            row.set_margin_start(12)
            row.set_margin_end(12)
            img = Gtk.Image.new_from_icon_name(icons[i % len(icons)])
            img.set_pixel_size(48)
            text = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
            a = Gtk.Label(label='Row %d: the quick brown fox jumps over the lazy dog' % i, xalign=0)
            b = Gtk.Label(label='Second line with some smaller detail text, item %d of 400' % i, xalign=0)
            b.add_css_class('dim-label')
            text.append(a)
            text.append(b)
            text.set_hexpand(True)
            row.append(img)
            row.append(text)
            row.append(Gtk.Button(label='Open'))
            box.append(row)
        self.sw.set_child(box)
        win.set_child(self.sw)
        win.maximize()
        win.present()
        self.adj = self.sw.get_vadjustment()
        GLib.timeout_add(2500, self.start_burst)     # settle after start-up

    def start_burst(self):
        self.t0 = GLib.get_monotonic_time()
        self.last = None
        self.cur = []
        self.sw.add_tick_callback(self.tick)
        return False

    def tick(self, widget, clock):
        now = clock.get_frame_time()
        if self.last is None:
            self.first_delay = now - self.t0
            self.t_start = now
        else:
            dt = now - self.last
            self.cur.append(dt)
            v = self.adj.get_value() + self.direction * SPEED * dt / 1e6
            lo, hi = self.adj.get_lower(), self.adj.get_upper() - self.adj.get_page_size()
            if v >= hi:
                v, self.direction = hi, -1
            elif v <= lo:
                v, self.direction = lo, 1
            self.adj.set_value(v)
        self.last = now
        if now - self.t_start < BURST_US:
            return True
        self.bursts.append((self.first_delay, self.cur))
        if len(self.bursts) >= BURSTS:
            self.report()
            self.quit()
        else:
            GLib.timeout_add(IDLE_MS, self.start_burst)
        return False

    def report(self):
        alld = [d for _, c in self.bursts for d in c]
        if not alld:
            print(json.dumps({'label': LABEL, 'error': 'no frames'}))
            return
        s = sorted(alld)
        ideal = len(self.bursts) * BURST_US / FRAME_US
        dropped = sum(max(0, round(d / FRAME_US) - 1) for d in alld)
        # the first 6 frames of each burst: where a slow ramp-up shows
        head = [d for _, c in self.bursts for d in c[:6]]
        res = {
            'label': LABEL,
            'bursts': len(self.bursts),
            'frames': len(alld),
            'ideal_frames': round(ideal),
            'dropped': dropped,
            'mean_ms': round(sum(alld) / len(alld) / 1000, 1),
            'p95_ms': round(s[int(len(s) * 0.95)] / 1000, 1),
            'max_ms': round(s[-1] / 1000, 1),
            'over25ms': sum(1 for d in alld if d > 25000),
            'head_mean_ms': round(sum(head) / len(head) / 1000, 1),
            'head_dropped': sum(max(0, round(d / FRAME_US) - 1) for d in head),
            'first_frame_ms': round(sum(f for f, _ in self.bursts) / len(self.bursts) / 1000, 1),
        }
        print(json.dumps(res))


Bench().run([])
