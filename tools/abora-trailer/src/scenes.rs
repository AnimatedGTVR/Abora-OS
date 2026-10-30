use std::io::{self, Write};

use crate::canvas::{lerp, scale, Canvas, Rgb};
use crate::font;

/// Scene names and lengths in seconds, played in this order.
pub const SCENES: [(&str, f32); 4] = [
    ("storm", 8.0),
    ("gather", 7.0),
    ("strike", 6.0),
    ("outro", 6.0),
];
const STORM: usize = 0;
const GATHER: usize = 1;
const STRIKE: usize = 2;
const OUTRO: usize = 3;

/// When the two bolts hit in the strike scene.
const BOLTS: [f32; 2] = [1.2, 2.0];

const SKY_TOP: Rgb = (3, 6, 14);
const SKY_BOTTOM: Rgb = (8, 15, 30);
const LOGO_LEFT: Rgb = (45, 115, 225);
const LOGO_RIGHT: Rgb = (140, 215, 255);
const HOT: Rgb = (255, 252, 230);
const GOLD: Rgb = (250, 196, 105);
const BOLT: Rgb = (235, 240, 255);
const RAIN_HEAD: Rgb = (190, 220, 245);
const RAIN_TAIL: Rgb = (30, 70, 135);
const DIM: Rgb = (120, 145, 180);

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
            tagline: String::new(),
            url: "aboraos.org".into(),
            from: 0,
            only: false,
            repeat: false,
            speed: 1.0,
            fps: 60,
            seed: 0x0AB0_2A05,
            frame: None,
            size: (140, 42),
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
    color: Rgb,
}

/// A grid of characters placed on screen, revealed cell by cell.
struct Art {
    grid: Vec<Vec<char>>,
    w: usize,
    h: usize,
    shown: Vec<Option<f32>>,
}

impl Art {
    fn new(grid: Vec<Vec<char>>) -> Self {
        let (w, h) = (grid.first().map_or(0, Vec::len), grid.len());
        Self {
            grid,
            w,
            h,
            shown: vec![None; w * h],
        }
    }

    fn mask(&self, x: usize, y: usize) -> bool {
        self.grid[y][x] != ' '
    }

    fn remaining(&self) -> usize {
        (0..self.h)
            .flat_map(|y| (0..self.w).map(move |x| (x, y)))
            .filter(|&(x, y)| self.mask(x, y) && self.shown[y * self.w + x].is_none())
            .count()
    }

    /// The lowest empty cell in a column: rain pools from the bottom up.
    fn lowest_empty(&self, x: usize) -> Option<usize> {
        (0..self.h)
            .rev()
            .find(|&y| self.mask(x, y) && self.shown[y * self.w + x].is_none())
    }

    fn show(&mut self, x: usize, y: usize, at: f32) {
        self.shown[y * self.w + x].get_or_insert(at);
    }

    fn show_all(&mut self, at: f32) {
        for y in 0..self.h {
            for x in 0..self.w {
                if self.mask(x, y) {
                    self.show(x, y, at);
                }
            }
        }
    }

    fn hide_all(&mut self) {
        self.shown.iter_mut().for_each(|s| *s = None);
    }
}

fn spaced(s: &str) -> Vec<Vec<char>> {
    vec![s.chars().flat_map(|c| [c, ' ']).collect()]
}

fn logo_art(w: u16, h: u16) -> Art {
    let title = font::title();
    if title[0].len() + 4 <= w as usize && h >= 26 {
        Art::new(title)
    } else if font::width("ABORA OS") + 4 <= w as usize && h >= 18 {
        Art::new(font::render("ABORA OS"))
    } else {
        Art::new(spaced("ABORA OS"))
    }
}

fn version_art(text: &str, w: u16) -> Art {
    if font::width(text) + 4 <= w as usize {
        Art::new(font::render(text))
    } else {
        Art::new(spaced(text))
    }
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
    logo: Art,
    version: Art,
    flash: f32,
    bolt: Vec<(i32, i32, char, f32)>,
    bolt_age: f32,
    strikes: usize,
}

impl Show {
    pub fn new(settings: Settings, w: u16, h: u16) -> Self {
        let text = format!("V{} {}", settings.version, settings.codename);
        let mut show = Self {
            rng: Rng(settings.seed | 1),
            canvas: Canvas::new(w, h),
            logo: logo_art(w, h),
            version: version_art(&text, w),
            scene: settings.from,
            settings,
            t: 0.0,
            clock: 0.0,
            started: false,
            drops: Vec::new(),
            sparks: Vec::new(),
            flash: 0.0,
            bolt: Vec::new(),
            bolt_age: 9.0,
            strikes: 0,
        };
        show.enter(show.scene);
        show
    }

    pub fn resize(&mut self, w: u16, h: u16) {
        self.canvas = Canvas::new(w, h);
        self.canvas.invalidate();
        self.logo = logo_art(w, h);
        let text = format!("V{} {}", self.settings.version, self.settings.codename);
        self.version = version_art(&text, w);
        self.drops.retain(|d| d.x < w as i32);
        let (scene, t) = (self.scene, self.t);
        self.enter(scene);
        self.t = t;
        if scene == GATHER {
            self.logo.show_all(self.clock - 1.0);
        }
    }

    /// Plays `seconds` into the current scene without a terminal (for --frame).
    pub fn preview(&mut self, seconds: f32) -> String {
        let mut left = seconds;
        while left > 0.0 {
            let dt = (1.0f32 / 60.0).min(left);
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
            STORM | GATHER => {
                self.logo.hide_all();
                self.version.hide_all();
            }
            STRIKE => {
                self.logo.show_all(self.clock - 2.0);
                self.version.hide_all();
            }
            _ => {
                self.logo.show_all(self.clock - 2.0);
                self.version.show_all(self.clock - 2.0);
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
            STRIKE => 0.15 + 0.6 * (1.0 - smooth(self.t / 2.5)),
            _ => 0.15 * (1.0 - smooth(self.t / 2.0)),
        }
    }

    /// Where the logo and the version line go: centred together.
    fn layout(&self) -> ((i32, i32), (i32, i32)) {
        let (w, h) = (self.canvas.w as i32, self.canvas.h as i32);
        let block = self.logo.h as i32 + 2 + self.version.h as i32 + 3;
        let top = ((h - block) / 2).max(0);
        let logo = ((w - self.logo.w as i32) / 2, top);
        let version = (
            (w - self.version.w as i32) / 2,
            top + self.logo.h as i32 + 2,
        );
        (logo, version)
    }

    fn update(&mut self, dt: f32) {
        let (w, h) = (self.canvas.w as i32, self.canvas.h as i32);
        self.flash *= (-dt * 7.0).exp();
        self.bolt_age += dt;

        let ((lx, ly), (vx, vy)) = self.layout();
        let strike_times: &[f32] = match self.scene {
            STORM => &[3.0, 6.3],
            STRIKE => &BOLTS,
            _ => &[],
        };
        if let Some(&at) = strike_times.get(self.strikes) {
            if self.t >= at {
                let target = if self.scene == STRIKE {
                    let share = if self.strikes == 0 { 0.25 } else { 0.75 };
                    (
                        vx + (self.version.w as f32 * share) as i32,
                        vy + self.version.h as i32 / 2,
                    )
                } else {
                    let x = self.rng.range(w as f32 * 0.2, w as f32 * 0.8) as i32;
                    (x, self.rng.range(h as f32 * 0.5, h as f32 * 0.85) as i32)
                };
                self.strike(target, self.scene == STRIKE);
                self.strikes += 1;
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
                len: (speed / 10.0) as u8 + self.rng.range(0.0, 2.0) as u8,
            };
            self.drops.push(drop);
        }

        // While gathering, aim extra drops at the letters so the logo is done in time.
        if self.scene == GATHER && self.t < 6.0 {
            let rate = self.logo.remaining() as f32 / (5.6 - self.t).max(0.3);
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
                            len: 4,
                        });
                    }
                }
                k -= 1.0;
            }
        }
        if self.scene == GATHER && self.t >= 6.0 {
            self.logo.show_all(self.clock);
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
                            logo.show(col as usize, row, clock);
                            landed.push((d.x as f32, (ly + row as i32) as f32, 1));
                            return false;
                        }
                    }
                }
            }
            if d.y >= (h - 1) as f32 {
                landed.push((d.x as f32, (h - 1) as f32, 3));
                return false;
            }
            true
        });
        for (x, y, count) in landed {
            for _ in 0..count {
                self.splash(x, y, (150, 200, 245), 1.0);
            }
        }
        self.sparks.retain_mut(|s| {
            s.life += dt;
            s.vy += 32.0 * dt;
            s.x += s.vx * dt;
            s.y += s.vy * dt;
            s.life < s.max
        });
    }

    fn splash(&mut self, x: f32, y: f32, color: Rgb, force: f32) {
        let spark = Spark {
            x,
            y: y - 0.2,
            vx: self.rng.range(-9.0, 9.0) * force,
            vy: self.rng.range(-11.0, -3.0) * force,
            life: 0.0,
            max: self.rng.range(0.25, 0.55) * force.sqrt(),
            ch: self.rng.pick(&['.', '\'', '`', ',', '*']),
            color,
        };
        self.sparks.push(spark);
    }

    /// A bolt from the top of the screen to `target`. A reveal strike burns the
    /// version text in from where it lands.
    fn strike(&mut self, (tx, ty): (i32, i32), reveal: bool) {
        self.flash = 0.9;
        self.bolt_age = 0.0;
        self.bolt.clear();
        let mut x = tx + self.rng.range(-14.0, 14.0) as i32;
        for y in 0..ty.max(1) {
            let left = ty - y;
            let need = tx - x;
            let dx = if need.abs() >= left {
                need.signum()
            } else {
                self.rng.pick(&[-1, -1, 0, 1, 1])
            };
            let ch = match dx {
                -1 => '/',
                1 => '\\',
                _ => '|',
            };
            self.bolt.push((x, y, ch, 1.0));
            x += dx;
            if self.rng.f() < 0.07 {
                let dir = self.rng.pick(&[-1, 1]);
                let mut bx = x;
                for by in y + 1..(y + self.rng.range(3.0, 7.0) as i32).min(ty) {
                    bx += dir;
                    self.bolt
                        .push((bx, by, if dir < 0 { '/' } else { '\\' }, 0.55));
                }
            }
        }
        for _ in 0..if reveal { 26 } else { 8 } {
            self.splash(tx as f32, ty as f32, GOLD, 1.8);
        }
        if reveal {
            let (_, (vx, vy)) = self.layout();
            let at = self.clock;
            let half = self.version.w / 2;
            let cols = if self.strikes == 0 {
                0..half
            } else {
                half..self.version.w
            };
            for y in 0..self.version.h {
                for x in cols.clone() {
                    if self.version.mask(x, y) {
                        let dx = (vx + x as i32 - tx) as f32 / 2.0;
                        let dy = (vy + y as i32 - ty) as f32;
                        self.version
                            .show(x, y, at + (dx * dx + dy * dy).sqrt() / 40.0);
                    }
                }
            }
        }
    }

    pub fn draw(&mut self, out: &mut impl Write) -> io::Result<()> {
        self.canvas.clear(SKY_TOP, SKY_BOTTOM);
        self.draw_rain();
        let ((lx, ly), (vx, vy)) = self.layout();
        if self.scene >= GATHER {
            self.draw_logo(lx, ly);
        }
        if self.scene >= STRIKE {
            self.draw_version(vx, vy);
        }
        self.draw_bolt();
        if self.scene == OUTRO {
            self.draw_outro(vy + self.version.h as i32 + 2);
        }

        if self.flash > 0.01 {
            let add = scale((140, 155, 210), self.flash);
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
        if self.scene == OUTRO {
            fade *= 1.0 - smooth((self.t - 4.6) / 1.4);
        }
        self.canvas.render(out, fade)
    }

    fn draw_rain(&mut self) {
        for d in &self.drops {
            let head = d.y.floor() as i32;
            for k in 0..=d.len as i32 {
                let t = k as f32 / (d.len as f32 + 1.0);
                let color = if k == 0 {
                    RAIN_HEAD
                } else {
                    lerp(RAIN_TAIL, SKY_TOP, t * 0.7)
                };
                let ch = if k == d.len as i32 { ':' } else { '|' };
                self.canvas.set(d.x, head - k, ch, color);
            }
        }
        for s in &self.sparks {
            let k = 1.0 - s.life / s.max;
            self.canvas.set(
                s.x.round() as i32,
                s.y.round() as i32,
                s.ch,
                lerp(SKY_BOTTOM, s.color, k),
            );
        }
    }

    fn draw_bolt(&mut self) {
        if self.bolt_age > 0.45 {
            return;
        }
        let k = 1.0 - self.bolt_age / 0.45;
        let flicker = if (0.08..0.13).contains(&self.bolt_age) {
            0.25
        } else {
            1.0
        };
        for &(x, y, ch, strength) in &self.bolt {
            self.canvas
                .set(x, y, ch, scale(BOLT, (k * flicker + 0.1) * strength));
            for dx in [-1, 1] {
                self.canvas
                    .tint_bg(x + dx, y, scale((35, 40, 90), k * strength));
            }
        }
    }

    fn draw_logo(&mut self, lx: i32, ly: i32) {
        let span = self.logo.w.max(2) as f32;
        for y in 0..self.logo.h {
            for x in 0..self.logo.w {
                if !self.logo.mask(x, y) {
                    continue;
                }
                let Some(at) = self.logo.shown[y * self.logo.w + x] else {
                    continue;
                };
                let mut color = lerp(LOGO_LEFT, LOGO_RIGHT, x as f32 / span);
                let age = self.clock - at;
                if age < 0.5 {
                    color = lerp((215, 235, 255), color, smooth(age.max(0.0) / 0.5));
                }
                self.canvas
                    .set(lx + x as i32, ly + y as i32, self.logo.grid[y][x], color);
            }
        }
    }

    fn draw_version(&mut self, vx: i32, vy: i32) {
        for y in 0..self.version.h {
            for x in 0..self.version.w {
                let Some(at) = self.version.shown[y * self.version.w + x] else {
                    continue;
                };
                let age = self.clock - at;
                if age < 0.0 {
                    continue;
                }
                let color = lerp(HOT, GOLD, smooth(age / 0.7));
                self.canvas
                    .set(vx + x as i32, vy + y as i32, self.version.grid[y][x], color);
            }
        }
    }

    fn draw_outro(&mut self, y: i32) {
        let w = self.canvas.w as i32;
        let mut row = y;
        if !self.settings.tagline.is_empty() {
            let tag = self.settings.tagline.clone();
            let k = smooth((self.t - 0.6) / 0.8);
            self.canvas
                .text((w - tag.len() as i32) / 2, row, &tag, scale(DIM, k));
            row += 2;
        }
        let url = self.settings.url.clone();
        let k = smooth((self.t - 1.0) / 0.8);
        self.canvas
            .text((w - url.len() as i32) / 2, row, &url, scale(LOGO_RIGHT, k));
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
            140,
            42,
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
        s.logo.show(col, bottom, 0.0);
        assert!(s.logo.lowest_empty(col).unwrap() < bottom);
    }

    #[test]
    fn two_bolts_reveal_the_whole_version() {
        let mut s = show(STRIKE);
        while s.t < BOLTS[1] + 1.5 {
            s.step(1.0 / 60.0);
        }
        assert_eq!(s.strikes, 2);
        assert_eq!(s.version.remaining(), 0);
    }

    #[test]
    fn every_frame_is_plain_ascii() {
        let mut s = show(STORM);
        let mut frames = 0;
        while s.step(1.0 / 20.0) {
            s.draw(&mut io::sink()).unwrap();
            let text = s.canvas.to_text();
            assert!(
                text.is_ascii(),
                "non-ASCII in scene {}: {:?}",
                s.scene,
                text.chars().find(|c| !c.is_ascii())
            );
            frames += 1;
            assert!(frames < 20 * 60, "the show never ended");
        }
        let total: f32 = SCENES.iter().map(|s| s.1).sum();
        assert!((frames as f32 / 20.0 - total).abs() < 1.0);
    }

    #[test]
    fn smaller_terminals_get_smaller_lettering() {
        assert_eq!(Show::new(Settings::default(), 140, 42).logo.h, 10);
        assert_eq!(Show::new(Settings::default(), 90, 30).logo.h, font::ROWS);
        let mut s = Show::new(Settings::default(), 50, 15);
        assert_eq!(s.logo.h, 1);
        s.draw(&mut io::sink()).unwrap();
    }

    #[test]
    fn only_plays_one_scene() {
        let mut s = Show::new(
            Settings {
                from: STRIKE,
                only: true,
                ..Settings::default()
            },
            140,
            42,
        );
        let mut steps = 0;
        while s.step(0.1) {
            steps += 1;
        }
        assert!((steps as f32 * 0.1 - SCENES[STRIKE].1).abs() < 0.3);
    }
}
