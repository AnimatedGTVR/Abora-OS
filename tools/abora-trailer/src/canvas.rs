use std::io::{self, Write};

pub type Rgb = (u8, u8, u8);

pub const BLACK: Rgb = (0, 0, 0);

#[derive(Clone, Copy, PartialEq, Eq, Debug)]
pub struct Cell {
    pub ch: char,
    pub fg: Rgb,
    pub bg: Rgb,
}

/// A frame of cells, drawn with 24-bit colour. Only cells that changed since
/// the previous frame are sent to the terminal.
pub struct Canvas {
    pub w: u16,
    pub h: u16,
    cells: Vec<Cell>,
    front: Vec<Option<Cell>>,
}

pub fn lerp(a: Rgb, b: Rgb, t: f32) -> Rgb {
    let t = t.clamp(0.0, 1.0);
    let mix = |x: u8, y: u8| (x as f32 + (y as f32 - x as f32) * t).round() as u8;
    (mix(a.0, b.0), mix(a.1, b.1), mix(a.2, b.2))
}

pub fn scale(c: Rgb, k: f32) -> Rgb {
    let k = k.max(0.0);
    let s = |x: u8| (x as f32 * k).round().min(255.0) as u8;
    (s(c.0), s(c.1), s(c.2))
}

impl Canvas {
    pub fn new(w: u16, h: u16) -> Self {
        let n = w as usize * h as usize;
        Self {
            w,
            h,
            cells: vec![
                Cell {
                    ch: ' ',
                    fg: BLACK,
                    bg: BLACK
                };
                n
            ],
            front: vec![None; n],
        }
    }

    fn idx(&self, x: i32, y: i32) -> Option<usize> {
        (x >= 0 && y >= 0 && x < self.w as i32 && y < self.h as i32)
            .then(|| y as usize * self.w as usize + x as usize)
    }

    /// Fills every cell with a vertical gradient from `top` to `bottom`.
    pub fn clear(&mut self, top: Rgb, bottom: Rgb) {
        let h = self.h.max(2) as f32 - 1.0;
        for y in 0..self.h {
            let bg = lerp(top, bottom, y as f32 / h);
            for x in 0..self.w {
                let i = y as usize * self.w as usize + x as usize;
                self.cells[i] = Cell {
                    ch: ' ',
                    fg: bg,
                    bg,
                };
            }
        }
    }

    /// The frame's characters only, one line per row.
    pub fn to_text(&self) -> String {
        self.cells
            .chunks(self.w as usize)
            .map(|row| {
                row.iter()
                    .map(|c| c.ch)
                    .collect::<String>()
                    .trim_end()
                    .to_string()
            })
            .collect::<Vec<_>>()
            .join("\n")
    }

    #[cfg(test)]
    pub fn get(&self, x: i32, y: i32) -> Option<Cell> {
        self.idx(x, y).map(|i| self.cells[i])
    }

    pub fn set(&mut self, x: i32, y: i32, ch: char, fg: Rgb) {
        if let Some(i) = self.idx(x, y) {
            self.cells[i].ch = ch;
            self.cells[i].fg = fg;
        }
    }

    pub fn tint_bg(&mut self, x: i32, y: i32, add: Rgb) {
        if let Some(i) = self.idx(x, y) {
            let b = self.cells[i].bg;
            self.cells[i].bg = (
                b.0.saturating_add(add.0),
                b.1.saturating_add(add.1),
                b.2.saturating_add(add.2),
            );
        }
    }

    pub fn text(&mut self, x: i32, y: i32, s: &str, fg: Rgb) {
        for (i, ch) in s.chars().enumerate() {
            self.set(x + i as i32, y, ch, fg);
        }
    }

    pub fn invalidate(&mut self) {
        self.front.iter_mut().for_each(|c| *c = None);
    }

    /// Writes the changed cells. `fade` scales every colour (0 = black).
    pub fn render(&mut self, out: &mut impl Write, fade: f32) -> io::Result<()> {
        let mut buf = String::with_capacity(self.cells.len() * 4);
        let mut cursor: Option<usize> = None;
        let mut fg: Option<Rgb> = None;
        let mut bg: Option<Rgb> = None;
        for i in 0..self.cells.len() {
            let c = self.cells[i];
            let cell = Cell {
                ch: c.ch,
                fg: scale(c.fg, fade),
                bg: scale(c.bg, fade),
            };
            if self.front[i] == Some(cell) {
                continue;
            }
            self.front[i] = Some(cell);
            if cursor != Some(i) {
                let (x, y) = (i % self.w as usize, i / self.w as usize);
                buf.push_str(&format!("\x1b[{};{}H", y + 1, x + 1));
            }
            if bg != Some(cell.bg) {
                buf.push_str(&format!(
                    "\x1b[48;2;{};{};{}m",
                    cell.bg.0, cell.bg.1, cell.bg.2
                ));
                bg = Some(cell.bg);
            }
            if cell.ch != ' ' && fg != Some(cell.fg) {
                buf.push_str(&format!(
                    "\x1b[38;2;{};{};{}m",
                    cell.fg.0, cell.fg.1, cell.fg.2
                ));
                fg = Some(cell.fg);
            }
            buf.push(cell.ch);
            // The last column wraps differently between terminals: always re-place.
            cursor = (i % self.w as usize != self.w as usize - 1).then_some(i + 1);
        }
        if !buf.is_empty() {
            out.write_all(buf.as_bytes())?;
        }
        out.flush()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_changed_cells_are_redrawn() {
        let mut c = Canvas::new(4, 2);
        let mut out = Vec::new();
        c.clear(BLACK, BLACK);
        c.render(&mut out, 1.0).unwrap();
        assert!(!out.is_empty());

        out.clear();
        c.clear(BLACK, BLACK);
        c.render(&mut out, 1.0).unwrap();
        assert!(out.is_empty(), "an identical frame writes nothing");

        c.set(2, 1, 'x', (255, 0, 0));
        c.render(&mut out, 1.0).unwrap();
        let s = String::from_utf8(out).unwrap();
        assert!(s.contains("\x1b[2;3H") && s.ends_with('x'), "{s:?}");
    }

    #[test]
    fn writes_outside_the_canvas_are_ignored() {
        let mut c = Canvas::new(2, 2);
        c.set(-1, 0, 'x', BLACK);
        c.set(5, 5, 'x', BLACK);
        assert!(c.get(5, 5).is_none());
    }

    #[test]
    fn colour_helpers() {
        assert_eq!(lerp((0, 0, 0), (100, 200, 50), 0.5), (50, 100, 25));
        assert_eq!(scale((100, 200, 250), 2.0), (200, 255, 255));
    }
}
