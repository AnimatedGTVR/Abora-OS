//! Plain-ASCII lettering: Abora's own title art, and a 5-row figlet-style
//! font for the version line.

/// Abora's ASCII title (assets/abora-title.txt), copied so the crate builds alone.
const TITLE: &str = include_str!("title.txt");

pub const ROWS: usize = 5;

fn glyph(c: char) -> [&'static str; ROWS] {
    match c.to_ascii_uppercase() {
        'A' => [
            "    _    ",
            "   / \\   ",
            "  / _ \\  ",
            " / ___ \\ ",
            "/_/   \\_\\",
        ],
        'B' => [" ____  ", "| __ ) ", "|  _ \\ ", "| |_) |", "|____/ "],
        'C' => ["  ____ ", " / ___|", "| |    ", "| |___ ", " \\____|"],
        'E' => [" _____ ", "| ____|", "|  _|  ", "| |___ ", "|_____|"],
        'I' => [" ___ ", "|_ _|", " | | ", " | | ", "|___|"],
        'L' => [" _     ", "| |    ", "| |    ", "| |___ ", "|_____|"],
        'N' => [" _   _ ", "| \\ | |", "|  \\| |", "| |\\  |", "|_| \\_|"],
        'O' => ["  ___  ", " / _ \\ ", "| | | |", "| |_| |", " \\___/ "],
        'R' => [" ____  ", "|  _ \\ ", "| |_) |", "|  _ < ", "|_| \\_\\"],
        'S' => [" ____  ", "/ ___| ", "\\___ \\ ", " ___) |", "|____/ "],
        'T' => [" _____ ", "|_   _|", "  | |  ", "  | |  ", "  |_|  "],
        'V' => [
            "__     __",
            "\\ \\   / /",
            " \\ \\ / / ",
            "  \\ V /  ",
            "   \\_/   ",
        ],
        'X' => ["__  __", "\\ \\/ /", " \\  / ", " /  \\ ", "/_/\\_\\"],
        '0' => ["  ___  ", " / _ \\ ", "| | | |", "| |_| |", " \\___/ "],
        '1' => [" _ ", "/ |", "| |", "| |", "|_|"],
        '2' => [" ____  ", "|___ \\ ", "  __) |", " / __/ ", "|_____|"],
        '3' => [" _____ ", "|___ / ", "  |_ \\ ", " ___) |", "|____/ "],
        '4' => [" _  _   ", "| || |  ", "| || |_ ", "|__   _|", "   |_|  "],
        '5' => [" ____  ", "| ___| ", "|___ \\ ", " ___) |", "|____/ "],
        '6' => ["  __   ", " / /_  ", "| '_ \\ ", "| (_) |", " \\___/ "],
        '7' => [" _____ ", "|___  |", "   / / ", "  / /  ", " /_/   "],
        '8' => ["  ___  ", " ( _ ) ", " / _ \\ ", "| (_) |", " \\___/ "],
        '9' => ["  ___  ", " / _ \\ ", "| (_) |", " \\__, |", "   /_/ "],
        '.' => ["   ", "   ", "   ", " _ ", "(_)"],
        '-' => ["       ", "       ", " _____ ", "|_____|", "       "],
        _ => ["    ", "    ", "    ", "    ", "    "],
    }
}

/// Renders `text` in the big font, as rows of characters.
pub fn render(text: &str) -> Vec<Vec<char>> {
    let mut rows = vec![Vec::new(); ROWS];
    for c in text.chars() {
        for (r, line) in glyph(c).iter().enumerate() {
            rows[r].extend(line.chars());
        }
    }
    rows
}

pub fn width(text: &str) -> usize {
    render(text)[0].len()
}

/// Abora's title art as equal-length rows.
pub fn title() -> Vec<Vec<char>> {
    let lines: Vec<&str> = TITLE.lines().collect();
    let w = lines.iter().map(|l| l.len()).max().unwrap_or(0);
    lines
        .iter()
        .map(|l| {
            let mut row: Vec<char> = l.chars().collect();
            row.resize(w, ' ');
            row
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_glyph_is_rectangular_ascii() {
        for c in "ABCEILNORSTVX0123456789.- ".chars() {
            let rows = glyph(c);
            let w = rows[0].len();
            for row in rows {
                assert_eq!(row.len(), w, "glyph {c:?} has ragged rows");
                assert!(row.is_ascii(), "glyph {c:?} is not ASCII");
            }
        }
    }

    #[test]
    fn the_title_is_ascii_and_rectangular() {
        let t = title();
        assert_eq!(t.len(), 10);
        assert!(t
            .iter()
            .all(|r| r.len() == t[0].len() && r.iter().all(char::is_ascii)));
    }

    #[test]
    fn the_version_line_fits_a_wide_terminal() {
        assert!(width("V4.2 SOLSTICE") <= 90, "{}", width("V4.2 SOLSTICE"));
    }
}
