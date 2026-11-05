// Running other programs without blocking the window.

namespace Flurry {

    public class Proc : Object {
        public int status = -1;
        public string out_text = "";
        public string err_text = "";
        public bool ok { get { return status == 0; } }

        /// The last few non-empty lines of stderr (or stdout), for error messages.
        public string tail (int lines = 6) {
            var text = err_text.strip () != "" ? err_text : out_text;
            var all = text.strip ().split ("\n");
            var start = int.max (0, all.length - lines);
            return string.joinv ("\n", all[start:all.length]).strip ();
        }
    }

    public string? find_program (string name) {
        return Environment.find_program_in_path (name);
    }

    SubprocessLauncher launcher_for (SubprocessFlags flags, string[]? env) {
        var launcher = new SubprocessLauncher (flags);
        if (env != null) {
            foreach (var pair in env) {
                var eq = pair.index_of_char ('=');
                if (eq > 0) launcher.setenv (pair[0:eq], pair[eq + 1:pair.length], true);
            }
        }
        return launcher;
    }

    /// Runs argv to completion and collects its output. Never throws: a program that can't start
    /// comes back with status -1 and the reason in err_text.
    public async Proc run (string[] argv, string[]? env = null, Cancellable? cancel = null) {
        var result = new Proc ();
        try {
            var launcher = launcher_for (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE, env);
            var process = launcher.spawnv (argv);
            string? out_text = null, err_text = null;
            yield process.communicate_utf8_async (null, cancel, out out_text, out err_text);
            result.status = process.get_if_exited () ? process.get_exit_status () : -1;
            result.out_text = out_text ?? "";
            result.err_text = err_text ?? "";
        } catch (Error e) {
            result.err_text = e.message;
        }
        return result;
    }

    /// A long-running command whose output is shown live (installs, updates, rebuilds).
    public class Job : Object {
        public string[] argv { get; construct; }
        public string[]? env { get; construct; }
        public StringBuilder log = new StringBuilder ();
        public signal void line (string text);

        public Job (string[] argv, string[]? env = null) {
            Object (argv: argv, env: env);
        }

        public async int run (Cancellable? cancel = null) {
            try {
                var launcher = launcher_for (SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_MERGE, env);
                var process = launcher.spawnv (argv);
                var reader = new DataInputStream (process.get_stdout_pipe ());
                string? text;
                while ((text = yield reader.read_line_utf8_async (Priority.DEFAULT, cancel)) != null) {
                    // Progress bars redraw with \r; keep only what the line ended as.
                    var parts = text.split ("\r");
                    var shown = parts[parts.length - 1];
                    log.append (shown).append_c ('\n');
                    line (shown);
                }
                yield process.wait_async (cancel);
                return process.get_if_exited () ? process.get_exit_status () : -1;
            } catch (Error e) {
                log.append (e.message).append_c ('\n');
                line (e.message);
                return -1;
            }
        }

        public string tail (int lines = 8) {
            var all = log.str.strip ().split ("\n");
            var start = int.max (0, all.length - lines);
            return string.joinv ("\n", all[start:all.length]).strip ();
        }
    }

    /// pkexec runs commands with a minimal environment and its own PATH, so every privileged
    /// command goes through an absolute path and an explicit env.
    public string[] as_root (string[] argv, string[] env = {}) {
        string[] out = { find_program ("pkexec") ?? "/run/wrappers/bin/pkexec", "env" };
        foreach (var e in env) out += e;
        foreach (var a in argv) out += a;
        return out;
    }

    public void launch_detached (string[] argv) {
        try {
            new SubprocessLauncher (SubprocessFlags.NONE).spawnv (argv);
        } catch (Error e) {
            warning ("could not start %s: %s", argv[0], e.message);
        }
    }
}
