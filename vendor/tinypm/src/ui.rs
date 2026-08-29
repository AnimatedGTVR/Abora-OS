use std::io::IsTerminal;
use std::time::Duration;

use indicatif::{ProgressBar, ProgressDrawTarget, ProgressStyle};

pub struct Activity {
    bar: ProgressBar,
    animated: bool,
}

impl Activity {
    pub fn start(message: String, enabled: bool) -> Self {
        let animated = enabled && std::io::stderr().is_terminal();
        let bar = if animated {
            ProgressBar::new_spinner()
        } else {
            ProgressBar::hidden()
        };
        if animated {
            bar.set_draw_target(ProgressDrawTarget::stderr());
            bar.set_style(
                ProgressStyle::with_template("{spinner:.cyan} {msg}")
                    .expect("static progress template is valid")
                    .tick_strings(&["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]),
            );
            bar.set_message(message);
            bar.enable_steady_tick(Duration::from_millis(80));
        }
        Self { bar, animated }
    }

    pub fn success(self, message: String) {
        if self.animated {
            self.bar.finish_with_message(format!("✓ {message}"));
        } else {
            println!("✓ {message}");
        }
    }

    pub fn failure(self, message: String) {
        if self.animated {
            self.bar.abandon_with_message(format!("✗ {message}"));
        } else {
            eprintln!("✗ {message}");
        }
    }
}
