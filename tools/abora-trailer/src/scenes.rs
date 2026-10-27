use std::f32::consts::TAU;
use std::io::{self, Write};

use crate::canvas::{lerp, scale, Canvas, Rgb};
use crate::font;

/// Scene names and lengths in seconds, played in this order.
pub const SCENES: [(&str, f32); 5] = [
    ("storm", 8.0),
    ("gather", 7.0),
    ("shine", 6.5),
    ("terminal", 13.0),
    ("finale", 10.0),
];
const STORM: usize = 0;
const GATHER: usize = 1;
const SHINE: usize = 2;
const TERMINAL: usize = 3;
const FINALE: usize = 4;

const SKY_TOP: Rgb = (2, 6, 16);
const SKY_BOTTOM: Rgb = (7, 17, 38);
const OCEAN: Rgb = (0, 110, 255);
const AQUA: Rgb = (90, 235, 255);
const WHITE: Rgb = (235, 246, 255);
const RAIN_HEAD: Rgb = (205, 238, 255);
const RAIN_TAIL: Rgb = (22, 70, 150);
const TEXT: Rgb = (200, 225, 255);
const DIM: Rgb = (105, 135, 175);
const GREEN: Rgb = (95, 225, 130);

pub struct Settings {
    pub version: String,
    pub codename: String,
    pub tagline: String,
    pub url: String,
    pub from: usize,
    pub only: bool,
    pub repeat: bool,
    pub speed: f32,
    pub fps: u32,
    pub seed: u64,
    pub frame: Option<f32>,
    pub size: (u16, u16),
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            version: "4.2".into(),
            codename: "SOLSTICE".into(),
            tagline: "NixOS, made friendly.".into(),
            url: "aboraos.org".into(),
            from: 0,
            only: false,
            repeat: false,
            speed: 1.0,
            fps: 60,
            seed: 0x0AB0_2A05,
            frame: None,
            size: (120, 40),
        }
    }
}

struct Rng(u64);

impl Rng {
    fn next(&mut self) -> u64 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 7;
        self.0 ^= self.0 << 17;
        self.0
    }
    fn f(&mut self) -> f32 {
        (self.next() >> 40) as f32 / (1u64 << 24) as f32
    }
    fn range(&mut self, a: f32, b: f32) -> f32 {
        a + (b - a) * self.f()
    }
    fn pick<T: Copy>(&mut self, items: &[T]) -> T {
        items[self.next() as usize % items.len()]
    }
}

fn smooth(t: f32) -> f32 {
    let t = t.clamp(0.0, 1.0);
    t * t * (3.0 - 2.0 * t)
}

struct Drop {
    x: i32,
    y: f32,
    speed: f32,
    len: u8,
}

struct Spark {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    life: f32,
    max: f32,
    ch: char,
}

struct Star {
    angle: f32,
    dist: f32,
}

/// The ABORA OS letters, filled cell by cell as rain collects in them.
struct Logo {
    grid: Vec<Vec<char>>,
    w: usize,
    h: usize,
    filled: Vec<Option<f32>>,
}

impl Logo {
    fn new(term_w: u16, term_h: u16) -> Self {
        let grid = if font::width("ABORA OS") + 4 <= term_w as usize && term_h >= 20 {
            font::render("ABORA OS")
        } else {
            vec!["A B O R A   O S".chars().collect()]
        };
        let (w, h) = (grid[0].len(), grid.len());
        Self {
            grid,
            w,
            h,
            filled: vec![None; w * h],
        }
    }

    fn mask(&self, x: usize, y: usize) -> bool {
        self.grid[y][x] != ' '
    }

    fn cells(&self) -> usize {
        (0..self.h)
            .map(|y| (0..self.w).filter(|&x| self.mask(x, y)).count())
            .sum()
    }

    fn remaining(&self) -> usize {
        self.cells() - self.filled.iter().filter(|f| f.is_some()).count()
    }

    /// The lowest empty letter cell in a column: rain pools from the bottom up.
    fn lowest_empty(&self, x: usize) -> Option<usize> {
        (0..self.h)
            .rev()
            .find(|&y| self.mask(x, y) && self.filled[y * self.w + x].is_none())
    }

    fn fill(&mut self, x: usize, y: usize, at: f32) {
        self.filled[y * self.w + x].get_or_insert(at);
    }

    fn fill_all(&mut self, at: f32) {
        for y in 0..self.h {
            for x in 0..self.w {
                if self.mask(x, y) {
                    self.fill(x, y, at);
                }
            }
        }
    }

    fn clear(&mut self) {
        self.filled.iter_mut().for_each(|f| *f = None);
    }
}

#[derive(Clone, Copy, PartialEq)]
enum Line {
    Prompt,
    Output,
}

struct ScriptLine {
    kind: Line,
    text: String,
    /// When each character appears (prompts type; output appears at once).
    times: Vec<f32>,
}

pub struct Show {
    pub settings: Settings,
    pub canvas: Canvas,
    rng: Rng,
    scene: usize,
    t: f32,
    clock: f32,
    started: bool,
    drops: Vec<Drop>,
    sparks: Vec<Spark>,
    stars: Vec<Star>,
    logo: Logo,
    flash: f32,
    bolt: Vec<(i32, i32, char)>,
    bolt_age: f32,
    strikes: u8,
    script: Vec<ScriptLine>,
}

impl Show {
    pub fn new(settings: Settings, w: u16, h: u16) -> Self {
        let mut show = Self {
            rng: Rng(settings.seed | 1),
            canvas: Canvas::new(w, h),
            logo: Logo::new(w, h),
            scene: settings.from,
            settings,
            t: 0.0,
            clock: 0.0,
            started: false,
            drops: Vec::new(),
            sparks: Vec::new(),
            stars: Vec::new(),
            flash: 0.0,
            bolt: Vec::new(),
            bolt_age: 9.0,
            strikes: 0,
            script: Vec::new(),
        };
        show.enter(show.scene);
        show
    }

    pub fn resize(&mut self, w: u16, h: u16) {
        self.canvas = Canvas::new(w, h);
        self.canvas.invalidate();
        let was_full = self.logo.remaining() == 0;
        self.logo = Logo::new(w, h);
        if was_full || self.scene > GATHER {
            self.logo.fill_all(self.clock - 1.0);
        }
        self.drops.retain(|d| d.x < w as i32);
        self.stars.clear();
    }

    /// Plays `seconds` into the current scene without a terminal (for --frame).
    pub fn preview(&mut self, seconds: f32) -> String {
        let fps: f32 = 60.0;
        let mut left = seconds;
        while left > 0.0 {
            let dt = (1.0 / fps).min(left);
            self.step(dt);
            left -= dt;
        }
        self.started = true;
        let _ = self.draw(&mut io::sink());
        self.canvas.to_text()
    }

    pub fn skip(&mut self) {
        self.t = SCENES[self.scene].1;
    }

    fn enter(&mut self, scene: usize) {
        self.scene = scene;
        self.t = 0.0;
        self.strikes = 0;
        match scene {
            STORM | GATHER => self.logo.clear(),
            SHINE | TERMINAL => self.logo.fill_all(self.clock - 2.0),
            _ => {
                self.drops.clear();
                self.sparks.clear();
                self.logo.fill_all(self.clock + 4.0);
            }
        }
        if scene == TERMINAL {
            self.drops.clear();
            self.sparks.clear();
            self.script = self.build_script(0.95);
        }
        if scene == FINALE {
            self.stars.clear();
            for _ in 0..(self.canvas.w as usize * self.canvas.h as usize / 28).max(60) {
                let star = Star {
                    angle: self.rng.range(0.0, TAU),
                    dist: self.rng.range(0.5, 40.0),
                };
                self.stars.push(star);
            }
        }
    }

    /// Advances time; false when the show is over.
    pub fn step(&mut self, dt: f32) -> bool {
        let dt = dt * self.settings.speed;
        self.t += dt;
        self.clock += dt;
        if self.t >= SCENES[self.scene].1 {
            let next = if self.settings.only {
                self.scene
            } else {
                self.scene + 1
            };
            if next >= SCENES.len() || (self.settings.only && !self.settings.repeat) {
                if !self.settings.repeat {
                    return false;
                }
                self.enter(if self.settings.only { self.scene } else { 0 });
            } else {
                self.enter(next);
            }
        }
        self.update(dt);
        true
    }

    fn rain_intensity(&self) -> f32 {
        match self.scene {
            STORM => 0.12 + 0.88 * smooth(self.t / 6.0),
            GATHER => 1.0,
            SHINE => 0.08 + 0.72 * (1.0 - smooth(self.t / 2.5)),
            _ => 0.0,
        }
    }

    fn logo_origin(&self) -> (i32, i32) {
        let (w, h) = (self.canvas.w as i32, self.canvas.h as i32);
        let below = if self.logo.h > 1 { 6 } else { 4 };
        let y = ((h - self.logo.h as i32 - below) / 2).max(1);
        ((w - self.logo.w as i32) / 2, y)
    }

    fn update(&mut self, dt: f32) {
        let (w, h) = (self.canvas.w as i32, self.canvas.h as i32);
        self.flash *= (-dt * 7.0).exp();
        self.bolt_age += dt;

        // Lightning in the storm, a double flicker each.
        if self.scene == STORM {
            for (i, at) in [3.0f32, 6.3].iter().enumerate() {
                if self.strikes == i as u8 && self.t >= *at {
                    self.strike();
                    self.strikes += 1;
                }
            }
        }
        if self.bolt_age > 0.11 && self.bolt_age - dt <= 0.11 && !self.bolt.is_empty() {
            self.flash = self.flash.max(0.45);
        }

        // Rain.
        let spawn = self.rain_intensity() * w as f32 * 0.55 * dt;
        let mut n = spawn.floor() as usize + usize::from(self.rng.f() < spawn.fract());
        while n > 0 {
            n -= 1;
            let speed = self.rng.range(28.0, 52.0);
            let drop = Drop {
                x: self.rng.range(0.0, w as f32) as i32,
                y: self.rng.range(-6.0, 0.0),
                speed,
                len: (speed / 9.0) as u8 + self.rng.range(0.0, 2.0) as u8,
            };
            self.drops.push(drop);
        }

        // While gathering, aim extra drops at letters so the logo is done in time.
        let (lx, ly) = self.logo_origin();
        if self.scene == GATHER && self.t < 6.0 {
            let left = self.logo.remaining() as f32;
            let rate = left / (5.6 - self.t).max(0.3);
            let mut k = rate * dt;
            while k > 0.0 {
                if self.rng.f() < k.min(1.0) {
                    let col = self.rng.range(0.0, self.logo.w as f32) as usize;
                    if self.logo.lowest_empty(col).is_some() {
                        let speed = self.rng.range(34.0, 52.0);
                        self.drops.push(Drop {
                            x: lx + col as i32,
                            y: self.rng.range(-4.0, 0.0),
                            speed,
                            len: 5,
                        });
                    }
                }
                k -= 1.0;
            }
        }
        if self.scene == GATHER && self.t >= 6.0 {
            self.logo.fill_all(self.clock);
        }

        let gathering = self.scene == GATHER;
        let mut landed = Vec::new();
        let clock = self.clock;
        let logo = &mut self.logo;
        self.drops.retain_mut(|d| {
            d.y += d.speed * dt;
            if gathering {
                let col = d.x - lx;
                if col >= 0 && (col as usize) < logo.w {
                    if let Some(row) = logo.lowest_empty(col as usize) {
                        if d.y >= (ly + row as i32) as f32 {
                            logo.fill(col as usize, row, clock);
                            landed.push((d.x as f32, (ly + row as i32) as f32, true));
                            return false;
                        }
                    }
                }
            }
            if d.y >= (h - 1) as f32 {
                landed.push((d.x as f32, (h - 1) as f32, false));
                return false;
            }
            true
        });
        for (x, y, in_logo) in landed {
            let count = if in_logo {
                1
            } else {
                2 + (self.rng.f() * 3.0) as usize
            };
            for _ in 0..count {
                let spark = Spark {
                    x,
                    y: y - 0.2,
                    vx: self.rng.range(-9.0, 9.0),
                    vy: self.rng.range(-11.0, -3.0),
                    life: 0.0,
                    max: self.rng.range(0.25, 0.55),
                    ch: self.rng.pick(&['.', '·', '\'', '`', ',']),
                };
                self.sparks.push(spark);
            }
        }
        self.sparks.retain_mut(|s| {
            s.life += dt;
            s.vy += 32.0 * dt;
            s.x += s.vx * dt;
            s.y += s.vy * dt;
            s.life < s.max
        });

        // Starfield warp.
        if self.scene == FINALE && self.t < 4.0 {
            let warp = 0.35 * (self.t * 1.25).exp();
            let max = (w.max(h * 2)) as f32 * 0.6;
            for s in &mut self.stars {
                s.dist += (1.5 + s.dist) * warp * dt;
                if s.dist > max {
                    s.dist = self.rng.range(0.3, 3.0);
                    s.angle = self.rng.range(0.0, TAU);
                }
            }
        }
        if self.scene == FINALE && self.t >= 4.0 && self.t - dt < 4.0 {
            self.flash = 1.0;
            self.stars.clear();
        }
    }

    fn strike(&mut self) {
        let (w, h) = (self.canvas.w as i32, self.canvas.h as i32);
        self.flash = 0.8;
        self.bolt_age = 0.0;
        self.bolt.clear();
        let mut x = self.rng.range(w as f32 * 0.2, w as f32 * 0.8) as i32;
        let end = self.rng.range(h as f32 * 0.5, h as f32 * 0.85) as i32;
        for y in 0..end {
            let dx = self.rng.pick(&[-1, -1, 0, 1, 1]);
            let ch = match dx {
                -1 => '╱',
                1 => '╲',
                _ => '│',
            };
            self.bolt.push((x, y, ch));
            x += dx;
            if self.rng.f() < 0.06 {
                let mut bx = x;
                for by in y..(y + self.rng.range(3.0, 8.0) as i32).min(end) {
                    bx += 1;
                    self.bolt.push((bx, by, '╲'));
                }
            }
        }
    }

    fn build_script(&mut self, start: f32) -> Vec<ScriptLine> {
        let title = {
            let lower = self.settings.codename.to_lowercase();
            let mut c = lower.chars();
            c.next()
                .map(|f| f.to_uppercase().collect::<String>() + c.as_str())
                .unwrap_or_default()
        };
        let steps: Vec<(&str, Vec<String>)> = vec![
            (
                "anix package install hello",
                vec![
                    "✓ hello is installed".into(),
                    "  no config edits, no rebuild".into(),
                ],
            ),
            (
                "anix doctor",
                vec![
                    "✓ bootloader   ✓ network   ✓ disk".into(),
                    "✓ desktop      ✓ updates   ✓ graphics".into(),
                ],
            ),
            (
                "anix set desktop gnome && anix apply",
                vec![
                    "● plan   ● snapshot   ● apply   ● verify".into(),
                    "✓ applied, with a rollback ready".into(),
                ],
            ),
            (
                "abora update",
                vec![format!(
                    "✓ Abora OS v{} {} is up to date",
                    self.settings.version, title
                )],
            ),
        ];
        let mut at = start;
        let mut lines = Vec::new();
        for (cmd, outputs) in steps {
            let mut times = Vec::new();
            at += 0.35;
            for _ in cmd.chars() {
                at += self.rng.range(0.025, 0.075);
                times.push(at);
            }
            lines.push(ScriptLine {
                kind: Line::Prompt,
                text: cmd.into(),
                times,
            });
            at += 0.3;
            for out in outputs {
                at += 0.16;
                lines.push(ScriptLine {
                    kind: Line::Output,
                    text: out,
                    times: vec![at],
                });
            }
            at += 0.75;
        }
        lines
    }

    pub fn draw(&mut self, out: &mut impl Write) -> io::Result<()> {
        let c = &mut self.canvas;
        c.clear(SKY_TOP, SKY_BOTTOM);
        if self.scene == TERMINAL && self.t > 0.6 || self.scene == FINALE {
            c.clear((1, 3, 9), (3, 8, 20));
        }

        self.draw_rain();
        self.draw_bolt();
        match self.scene {
            GATHER => self.draw_logo(None, true),
            SHINE => {
                self.draw_logo(Some((self.t - 0.5) / 2.0), false);
                self.draw_titles(2.3, 3.6);
            }
            TERMINAL => self.draw_terminal(),
            FINALE => self.draw_finale(),
            _ => {}
        }

        let flash = self.flash;
        if flash > 0.01 {
            let add = scale((150, 170, 230), flash);
            for y in 0..self.canvas.h as i32 {
                for x in 0..self.canvas.w as i32 {
                    self.canvas.tint_bg(x, y, add);
                }
            }
        }

        let mut fade = 1.0;
        if !self.started {
            fade = smooth(self.clock / 1.2);
            self.started = self.clock > 1.2;
        }
        if self.scene == FINALE {
            fade *= 1.0 - smooth((self.t - 8.8) / 1.2);
        }
        self.canvas.render(out, fade)
    }

    fn draw_rain(&mut self) {
        let c = &mut self.canvas;
        for d in &self.drops {
            let head = d.y.floor() as i32;
            for k in 0..=d.len as i32 {
                let y = head - k;
                let t = k as f32 / (d.len as f32 + 1.0);
                let color = if k == 0 {
                    RAIN_HEAD
                } else {
                    lerp(RAIN_TAIL, SKY_TOP, t * 0.8)
                };
                let color = if k == 1 {
                    lerp(RAIN_HEAD, RAIN_TAIL, 0.35)
                } else {
                    color
                };
                let ch = if k == d.len as i32 { '╵' } else { '│' };
                c.set(d.x, y, ch, color);
            }
        }
        for s in &self.sparks {
            let k = 1.0 - s.life / s.max;
            c.set(
                s.x.round() as i32,
                s.y.round() as i32,
                s.ch,
                lerp(SKY_BOTTOM, (170, 215, 255), k),
            );
        }
    }

    fn draw_bolt(&mut self) {
        if self.bolt_age > 0.4 {
            return;
        }
        let k = 1.0 - self.bolt_age / 0.4;
        let flicker = if (0.08..0.13).contains(&self.bolt_age) {
            0.3
        } else {
            1.0
        };
        for &(x, y, ch) in &self.bolt {
            self.canvas.set(x, y, ch, scale(WHITE, k * flicker + 0.15));
            for dx in [-1, 1] {
                self.canvas.tint_bg(x + dx, y, scale((30, 35, 80), k));
            }
        }
    }

    /// `sweep` is the shine band's progress (0..1), `ghost` hints unfilled letters.
    fn draw_logo(&mut self, sweep: Option<f32>, ghost: bool) {
        let (lx, ly) = self.logo_origin();
        let glow = if self.scene == FINALE {
            1.0 + 0.18 * (self.clock * 2.6).sin()
        } else {
            1.0
        };
        let span = self.logo.w as f32 + 30.0;
        for y in 0..self.logo.h {
            for x in 0..self.logo.w {
                if !self.logo.mask(x, y) {
                    continue;
                }
                let (cx, cy) = (lx + x as i32, ly + y as i32);
                let Some(at) = self.logo.filled[y * self.logo.w + x] else {
                    if ghost {
                        self.canvas.tint_bg(cx, cy, (0, 5, 12));
                    }
                    continue;
                };
                let ch = self.logo.grid[y][x];
                let mut color = lerp(OCEAN, AQUA, x as f32 / self.logo.w.max(2) as f32);
                if !font::is_face(ch) {
                    color = scale(color, 0.5);
                }
                let age = self.clock - at;
                if age < 0.6 {
                    color = lerp(WHITE, color, smooth(age.max(0.0) / 0.6));
                }
                if let Some(p) = sweep {
                    let band = p * span - 15.0;
                    let dist = (x as f32 - band - y as f32 * 1.6).abs();
                    if dist < 4.0 {
                        color = lerp(color, WHITE, (1.0 - dist / 4.0) * 0.9);
                    }
                }
                self.canvas.set(cx, cy, ch, scale(color, glow));
            }
        }
    }

    /// The spaced-out version line and the typed tagline under the logo.
    fn draw_titles(&mut self, version_at: f32, tagline_at: f32) {
        let (_, ly) = self.logo_origin();
        let w = self.canvas.w as i32;
        let base = ly + self.logo.h as i32 + 2;
        let spaced = |s: &str| {
            s.chars()
                .map(|c| c.to_string())
                .collect::<Vec<_>>()
                .join(" ")
        };
        let version = format!(
            "{}   ·   {}",
            spaced(&format!("v{}", self.settings.version)),
            spaced(&self.settings.codename)
        );
        let split = version.find('·').unwrap_or(0);
        let shown =
            ((self.t - version_at) / 1.1 * version.chars().count() as f32).max(0.0) as usize;
        let x0 = (w - version.chars().count() as i32) / 2;
        for (i, ch) in version.chars().enumerate().take(shown) {
            let color = if version.char_indices().nth(i).map_or(0, |(b, _)| b) > split {
                AQUA
            } else {
                TEXT
            };
            self.canvas.set(x0 + i as i32, base, ch, color);
        }

        let tag = &self.settings.tagline;
        let typed = ((self.t - tagline_at) * 18.0).max(0.0) as usize;
        if self.t >= tagline_at {
            let x0 = (w - tag.chars().count() as i32) / 2;
            let n = typed.min(tag.chars().count());
            let text: String = tag.chars().take(n).collect();
            self.canvas.text(x0, base + 2, &text, DIM);
            if (self.clock * 2.0).fract() < 0.55 {
                self.canvas.set(x0 + n as i32, base + 2, '▌', AQUA);
            }
        }
    }

    fn draw_terminal(&mut self) {
        let (w, h) = (self.canvas.w as i32, self.canvas.h as i32);
        if self.t < 0.6 {
            // A bright line wipes the title away from the top.
            let line = (smooth(self.t / 0.6) * h as f32) as i32;
            self.draw_logo(None, false);
            self.draw_titles(-10.0, -10.0);
            for y in 0..line.min(h) {
                for x in 0..w {
                    self.canvas.set(x, y, ' ', (0, 0, 0));
                    self.canvas.set_bg(x, y, (1, 3, 9));
                }
            }
            for x in 0..w {
                self.canvas.set(x, line, '━', AQUA);
            }
            return;
        }

        let bw = (w - 4).min(76);
        let bh = (h - 4).min(18);
        let (x0, y0) = ((w - bw) / 2, (h - bh) / 2);
        let appear = smooth((self.t - 0.6) / 0.3);
        let border = scale((40, 110, 200), appear);
        let panel = scale((8, 14, 28), appear);
        for y in y0..y0 + bh {
            for x in x0..x0 + bw {
                self.canvas.set_bg(x, y, panel);
            }
        }
        for x in x0..x0 + bw {
            self.canvas.set(x, y0, '─', border);
            self.canvas.set(x, y0 + 2, '─', scale(border, 0.6));
            self.canvas.set(x, y0 + bh - 1, '─', border);
        }
        for y in y0..y0 + bh {
            self.canvas.set(x0, y, '│', border);
            self.canvas.set(x0 + bw - 1, y, '│', border);
        }
        for (x, y, ch) in [
            (x0, y0, '╭'),
            (x0 + bw - 1, y0, '╮'),
            (x0, y0 + bh - 1, '╰'),
            (x0 + bw - 1, y0 + bh - 1, '╯'),
        ] {
            self.canvas.set(x, y, ch, border);
        }
        self.canvas.set(x0, y0 + 2, '├', scale(border, 0.6));
        self.canvas
            .set(x0 + bw - 1, y0 + 2, '┤', scale(border, 0.6));
        for (i, color) in [(255, 95, 86), (255, 189, 46), (39, 201, 63)]
            .into_iter()
            .enumerate()
        {
            self.canvas
                .set(x0 + 3 + i as i32 * 2, y0 + 1, '●', scale(color, appear));
        }
        let title = format!("abora@{} ~", self.settings.codename.to_lowercase());
        self.canvas.text(
            x0 + (bw - title.chars().count() as i32) / 2,
            y0 + 1,
            &title,
            scale(DIM, appear),
        );

        let rows = (bh - 5).max(1) as usize;
        let mut visible: Vec<(Line, String, bool)> = Vec::new();
        for line in &self.script {
            let n = line.times.iter().filter(|&&at| self.t >= at).count();
            if n == 0 {
                if line.kind == Line::Prompt && visible.last().is_none_or(|l| !l.2) {
                    let ready = line.times[0] - 0.35;
                    if self.t >= ready {
                        visible.push((Line::Prompt, String::new(), true));
                    }
                }
                break;
            }
            let text = if line.kind == Line::Prompt {
                line.text.chars().take(n).collect()
            } else {
                line.text.clone()
            };
            let typing = line.kind == Line::Prompt && n < line.text.chars().count();
            visible.push((line.kind, text, typing));
            if typing {
                break;
            }
        }
        let skip = visible.len().saturating_sub(rows);
        let blink = (self.clock * 2.0).fract() < 0.55;
        let last = visible.len().saturating_sub(1);
        for (row, (i, (kind, text, _))) in visible.iter().enumerate().skip(skip).enumerate() {
            let y = y0 + 3 + row as i32;
            let mut x = x0 + 2;
            if *kind == Line::Prompt {
                self.canvas.text(x, y, "➜", AQUA);
                self.canvas.text(x + 2, y, "~", (60, 140, 255));
                x += 4;
                self.canvas.text(x, y, text, WHITE);
                if i == last && blink {
                    self.canvas
                        .set(x + text.chars().count() as i32, y, '█', AQUA);
                }
            } else {
                for (k, ch) in text.chars().enumerate() {
                    let color = match ch {
                        '✓' => GREEN,
                        '●' => AQUA,
                        _ => (170, 190, 215),
                    };
                    self.canvas.set(x + k as i32, y, ch, color);
                }
            }
        }
    }

    fn draw_finale(&mut self) {
        let (w, h) = (self.canvas.w as f32, self.canvas.h as f32);
        let (cx, cy) = (w / 2.0, h / 2.0);
        let max = w.max(h * 2.0) * 0.6;
        let streak = self.t > 2.2;
        for s in &self.stars {
            let (dx, dy) = (s.angle.cos(), s.angle.sin());
            let (x, y) = (cx + dx * s.dist * 2.0, cy + dy * s.dist);
            let k = (s.dist / max).min(1.0);
            let ch = match s.dist {
                d if d < 5.0 => '·',
                d if d < 14.0 => '•',
                _ => '✦',
            };
            let color = lerp((70, 110, 230), WHITE, k);
            if streak {
                let trail = if dy.abs() < 0.35 {
                    '─'
                } else if dx.abs() < 0.35 {
                    '│'
                } else if dx * dy > 0.0 {
                    '╲'
                } else {
                    '╱'
                };
                for t in 1..=2 {
                    let back = s.dist * (1.0 - 0.08 * t as f32);
                    self.canvas.set(
                        (cx + dx * back * 2.0) as i32,
                        (cy + dy * back) as i32,
                        trail,
                        scale(color, 0.55),
                    );
                }
            }
            self.canvas.set(x as i32, y as i32, ch, color);
        }
        if self.t >= 4.0 {
            self.draw_logo(None, false);
            let (_, ly) = self.logo_origin();
            let base = ly + self.logo.h as i32 + 2;
            let w = self.canvas.w as i32;
            let spaced = |s: &str| {
                s.chars()
                    .map(|c| c.to_string())
                    .collect::<Vec<_>>()
                    .join(" ")
            };
            let version = format!(
                "{}   ·   {}",
                spaced(&format!("v{}", self.settings.version)),
                spaced(&self.settings.codename)
            );
            let k = smooth((self.t - 4.8) / 0.8);
            self.canvas.text(
                (w - version.chars().count() as i32) / 2,
                base,
                &version,
                scale(TEXT, k),
            );
            let url = self.settings.url.clone();
            let k = smooth((self.t - 5.6) / 0.8);
            self.canvas.text(
                (w - url.chars().count() as i32) / 2,
                base + 2,
                &url,
                scale(AQUA, k),
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn show(scene: usize) -> Show {
        Show::new(
            Settings {
                from: scene,
                ..Settings::default()
            },
            120,
            40,
        )
    }

    #[test]
    fn the_logo_fills_completely_during_gather() {
        let mut s = show(GATHER);
        assert!(s.logo.remaining() > 0);
        while s.scene == GATHER {
            assert!(s.step(1.0 / 60.0));
        }
        assert_eq!(s.logo.remaining(), 0);
    }

    #[test]
    fn rain_pools_from_the_bottom_of_each_letter() {
        let mut s = show(GATHER);
        let col = (0..s.logo.w)
            .find(|&x| s.logo.mask(x, s.logo.h - 1))
            .unwrap();
        let bottom = s.logo.lowest_empty(col).unwrap();
        s.logo.fill(col, bottom, 0.0);
        assert!(s.logo.lowest_empty(col).unwrap() < bottom);
    }

    #[test]
    fn the_whole_show_plays_and_ends() {
        let mut s = show(STORM);
        let mut out = Vec::new();
        let mut frames = 0;
        while s.step(1.0 / 30.0) {
            s.draw(&mut out).unwrap();
            frames += 1;
            assert!(frames < 30 * 120, "the show never ended");
        }
        let total: f32 = SCENES.iter().map(|s| s.1).sum();
        assert!((frames as f32 / 30.0 - total).abs() < 1.0);
    }

    #[test]
    fn small_terminals_get_a_one_line_logo() {
        let s = Show::new(Settings::default(), 50, 15);
        assert_eq!(s.logo.h, 1);
        let mut s = s;
        s.draw(&mut Vec::new()).unwrap();
    }

    #[test]
    fn the_terminal_scene_types_every_command() {
        let mut s = show(TERMINAL);
        let last = s.script.last().unwrap().times.last().copied().unwrap();
        assert!(
            last < SCENES[TERMINAL].1,
            "script runs past the scene ({last}s)"
        );
        while s.scene == TERMINAL && s.step(1.0 / 60.0) {}
    }

    #[test]
    fn only_plays_one_scene() {
        let mut s = Show::new(
            Settings {
                from: SHINE,
                only: true,
                ..Settings::default()
            },
            100,
            30,
        );
        let mut steps = 0;
        while s.step(0.1) {
            steps += 1;
        }
        assert!((steps as f32 * 0.1 - SCENES[SHINE].1).abs() < 0.3);
    }
}
