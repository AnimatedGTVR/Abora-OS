//! abora-trailer: an animated Abora OS title sequence for trailers, played in
//! the terminal. Record it full-screen; see --help for the knobs.

mod canvas;
mod font;
mod scenes;

use std::io::{self, BufWriter, Write};
use std::time::{Duration, Instant};

use crossterm::event::{self, Event, KeyCode, KeyEvent, KeyModifiers};
use crossterm::{cursor, execute, terminal};

use scenes::{Settings, Show, SCENES};

const HELP: &str = "\
abora-trailer: an animated Abora OS title sequence, for recording trailers

Usage: abora-trailer [options]

  --version <text>    version shown under the logo        (default 4.2)
  --codename <text>   release codename                    (default SOLSTICE)
  --tagline <text>    line typed under the version        (default \"NixOS, made friendly.\")
  --url <text>        address shown at the end            (default aboraos.org)
  --from <scene>      start at storm, gather, shine, terminal or finale
  --only <scene>      play just that scene
  --loop              start over after the finale
  --speed <x>         playback speed (0.5 = half speed)
  --fps <n>           frames per second                   (default 60)
  --seed <n>          randomness seed, for a repeatable take
  --frame <scene:s>   print one frame as plain text and exit (e.g. gather:4.5)
  --size <WxH>        terminal size for --frame           (default 120x40)

Keys: space or → skips to the next scene, p pauses, q / Esc / Ctrl-C quits.
Record in a large, dark terminal with a font that has box-drawing characters.";

fn parse_args() -> Result<Settings, String> {
    let mut s = Settings::default();
    let mut args = std::env::args().skip(1);
    while let Some(arg) = args.next() {
        let mut value = |name: &str| args.next().ok_or(format!("{name} needs a value"));
        match arg.as_str() {
            "-h" | "--help" => {
                println!("{HELP}");
                std::process::exit(0);
            }
            "--version" => s.version = value("--version")?,
            "--codename" => s.codename = value("--codename")?.to_uppercase(),
            "--tagline" => s.tagline = value("--tagline")?,
            "--url" => s.url = value("--url")?,
            "--from" | "--only" => {
                let name = value(&arg)?;
                let i = SCENES.iter().position(|(n, _)| *n == name).ok_or(format!(
                    "unknown scene {name}; scenes: storm gather shine terminal finale"
                ))?;
                s.from = i;
                s.only = arg == "--only";
            }
            "--loop" => s.repeat = true,
            "--speed" => {
                s.speed = value("--speed")?
                    .parse()
                    .map_err(|_| "--speed needs a number")?;
                if !(0.05..=10.0).contains(&s.speed) {
                    return Err("--speed must be between 0.05 and 10".into());
                }
            }
            "--fps" => {
                s.fps = value("--fps")?
                    .parse()
                    .map_err(|_| "--fps needs a whole number")?;
                s.fps = s.fps.clamp(10, 240);
            }
            "--seed" => {
                s.seed = value("--seed")?
                    .parse()
                    .map_err(|_| "--seed needs a whole number")?
            }
            "--frame" => {
                let v = value("--frame")?;
                let (name, secs) = v.split_once(':').ok_or("--frame needs scene:seconds")?;
                let i = SCENES
                    .iter()
                    .position(|(n, _)| *n == name)
                    .ok_or(format!("unknown scene {name}"))?;
                s.from = i;
                s.frame = Some(secs.parse().map_err(|_| "--frame needs scene:seconds")?);
            }
            "--size" => {
                let v = value("--size")?;
                let (w, h) = v.split_once('x').ok_or("--size needs WxH")?;
                s.size = (
                    w.parse().map_err(|_| "--size needs WxH")?,
                    h.parse().map_err(|_| "--size needs WxH")?,
                );
            }
            other => return Err(format!("unknown option {other} (see --help)")),
        }
    }
    Ok(s)
}

/// Restores the terminal however the program ends.
struct TerminalGuard;

impl TerminalGuard {
    fn enter() -> io::Result<Self> {
        terminal::enable_raw_mode()?;
        execute!(io::stdout(), terminal::EnterAlternateScreen, cursor::Hide)?;
        Ok(Self)
    }
}

impl Drop for TerminalGuard {
    fn drop(&mut self) {
        let _ = execute!(io::stdout(), cursor::Show, terminal::LeaveAlternateScreen);
        let _ = io::stdout().write_all(b"\x1b[0m");
        let _ = terminal::disable_raw_mode();
    }
}

enum Key {
    Quit,
    Skip,
    Pause,
}

fn read_key() -> io::Result<Option<Key>> {
    while event::poll(Duration::ZERO)? {
        if let Event::Key(KeyEvent {
            code, modifiers, ..
        }) = event::read()?
        {
            let key = match code {
                KeyCode::Char('q') | KeyCode::Esc => Key::Quit,
                KeyCode::Char('c') if modifiers.contains(KeyModifiers::CONTROL) => Key::Quit,
                KeyCode::Char(' ') | KeyCode::Right | KeyCode::Enter => Key::Skip,
                KeyCode::Char('p') => Key::Pause,
                _ => continue,
            };
            return Ok(Some(key));
        }
    }
    Ok(None)
}

fn run(settings: Settings) -> io::Result<()> {
    let _guard = TerminalGuard::enter()?;
    let mut out = BufWriter::with_capacity(1 << 20, io::stdout());
    let (w, h) = terminal::size()?;
    let mut show = Show::new(settings, w, h);
    let frame = Duration::from_secs_f64(1.0 / show.settings.fps as f64);
    let mut last = Instant::now();
    let mut paused = false;

    loop {
        let started = Instant::now();
        match read_key()? {
            Some(Key::Quit) => return Ok(()),
            Some(Key::Skip) => show.skip(),
            Some(Key::Pause) => paused = !paused,
            None => {}
        }
        let (w, h) = terminal::size()?;
        if (w, h) != (show.canvas.w, show.canvas.h) {
            show.resize(w, h);
            out.write_all(b"\x1b[2J")?;
        }

        let now = Instant::now();
        let dt = (now - last).as_secs_f32().min(0.1);
        last = now;
        if !paused && !show.step(dt) {
            return Ok(());
        }
        show.draw(&mut out)?;

        if let Some(rest) = frame.checked_sub(started.elapsed()) {
            std::thread::sleep(rest);
        }
    }
}

fn main() {
    let settings = match parse_args() {
        Ok(s) => s,
        Err(err) => {
            eprintln!("abora-trailer: {err}");
            std::process::exit(2);
        }
    };
    if let Some(at) = settings.frame {
        let (w, h) = settings.size;
        println!("{}", Show::new(settings, w, h).preview(at));
        return;
    }
    if let Err(err) = run(settings) {
        eprintln!("abora-trailer: {err}");
        std::process::exit(1);
    }
}
