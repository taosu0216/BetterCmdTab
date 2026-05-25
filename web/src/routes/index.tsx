import { createFileRoute } from "@tanstack/react-router";
import { AnimatePresence, MotionConfig, motion } from "motion/react";
import { useEffect, useState } from "react";
import { createPortal } from "react-dom";

export const Route = createFileRoute("/")({
  component: Home,
});

const REPO = "https://github.com/rokartur/BetterCmdTab";

const EASE = [0.22, 1, 0.36, 1] as const;

const reveal = {
  hidden: { opacity: 0, y: 16 },
  show: { opacity: 1, y: 0, transition: { duration: 0.5, ease: EASE } },
};

const stagger = {
  hidden: {},
  show: { transition: { staggerChildren: 0.05, delayChildren: 0.04 } },
};

const inView = {
  variants: stagger,
  initial: "hidden",
  whileInView: "show",
  viewport: { once: true, margin: "-60px" },
} as const;

const shots: Array<[string, string]> = [
  ["/screenshots/list.svg", "Classic vertical list"],
  ["/screenshots/grid.svg", "Grid of app icons"],
];

const features: Array<[string, string]> = [
  ["Two layouts", "classic list, or a grid of icons"],
  ["Window switching", "Cmd+` cycles windows of the front app"],
  ["Letter-prefix jump", "type a name to filter and jump"],
  ["Quick actions", "quit, close, minimize, hide inline"],
  ["Liquid Glass", "system material on macOS 26"],
  ["Multi-monitor", "opens on the screen under the cursor"],
  ["Menu bar agent", "no dock icon, no main window, no Electron"],
];

const shortcuts: Array<[string, string]> = [
  ["Cmd Tab", "Next app"],
  ["Cmd Tab + Shift", "Previous app"],
  ["Cmd `", "Next window of current app"],
  ["Cmd Shift `", "Previous window of current app"],
  ["Cmd letters", "Jump to app starting with that letter"],
  ["Cmd Q", "Quit the highlighted app"],
  ["Cmd W", "Close the highlighted window"],
  ["Cmd M", "Minimize the highlighted window"],
  ["Cmd H", "Hide / unhide the highlighted app"],
  ["Cmd Esc", "Cancel without activating"],
  ["Release Cmd", "Activate the highlighted row"],
];

interface GhAsset {
  name: string;
  browser_download_url: string;
}

interface GhRelease {
  tag_name: string;
  assets: GhAsset[];
}

interface Release {
  version: string | null;
  dmgUrl: string;
  ready: boolean;
}

function useLatestRelease(): Release {
  const [rel, setRel] = useState<Release>({
    version: null,
    dmgUrl: `${REPO}/releases/latest`,
    ready: false,
  });

  useEffect(() => {
    const ctrl = new AbortController();
    fetch("https://api.github.com/repos/rokartur/BetterCmdTab/releases/latest", {
      headers: { Accept: "application/vnd.github+json" },
      signal: ctrl.signal,
    })
      .then((r) => (r.ok ? (r.json() as Promise<GhRelease>) : Promise.reject(r.status)))
      .then((d) => {
        const dmg = d.assets.find((a) => a.name.endsWith(".dmg"));
        setRel({
          version: d.tag_name,
          dmgUrl: dmg?.browser_download_url ?? `${REPO}/releases/latest`,
          ready: true,
        });
      })
      .catch(() => {
        if (!ctrl.signal.aborted) setRel((p) => ({ ...p, ready: true }));
      });
    return () => ctrl.abort();
  }, []);

  return rel;
}

function Shots() {
  const [open, setOpen] = useState<number | null>(null);

  useEffect(() => {
    if (open === null) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setOpen(null);
    };
    window.addEventListener("keydown", onKey);
    document.body.style.overflow = "hidden";
    return () => {
      window.removeEventListener("keydown", onKey);
      document.body.style.overflow = "";
    };
  }, [open]);

  const active = open === null ? null : shots[open];

  return (
    <>
      <motion.section className="shots" {...inView}>
        {shots.map(([src, caption], i) => (
          <motion.figure key={src} className="shot" variants={reveal}>
            <motion.img
              src={src}
              alt={caption}
              loading="lazy"
              role="button"
              tabIndex={0}
              aria-label={`Enlarge: ${caption}`}
              onClick={() => setOpen(i)}
              onKeyDown={(e) => {
                if (e.key === "Enter" || e.key === " ") {
                  e.preventDefault();
                  setOpen(i);
                }
              }}
              whileHover={{ scale: 1.02 }}
              transition={{ duration: 0.3, ease: EASE }}
            />
            <figcaption>{caption}</figcaption>
          </motion.figure>
        ))}
      </motion.section>

      {createPortal(
        <AnimatePresence>
          {active && (
            <motion.div
              className="lightbox"
              onClick={() => setOpen(null)}
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              transition={{ duration: 0.2, ease: EASE }}
            >
              <motion.img
                src={active[0]}
                alt={active[1]}
                className="lightbox-img"
                initial={{ opacity: 0, scale: 0.94 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0, scale: 0.96 }}
                transition={{ duration: 0.26, ease: EASE }}
              />
              <span className="lightbox-hint">Esc · click to close</span>
            </motion.div>
          )}
        </AnimatePresence>,
        document.body,
      )}
    </>
  );
}

function Rows({ rows, combo }: { rows: Array<[string, string]>; combo?: boolean }) {
  return (
    <motion.ul className="grid" variants={stagger}>
      {rows.map(([key, desc]) => (
        <motion.li key={key} variants={reveal} whileHover={{ x: 4 }}>
          <span className={combo ? "key combo" : "key"}>{key}</span>
          <span className="desc">{desc}</span>
        </motion.li>
      ))}
    </motion.ul>
  );
}

function Home() {
  const { version, dmgUrl } = useLatestRelease();

  return (
    <MotionConfig reducedMotion="user">
      <main className="page">
        <motion.header className="intro" variants={stagger} initial="hidden" animate="show">
          <motion.h1 className="brand" variants={reveal}>
            <img className="brand-icon" src="/icon.png" alt="" width={26} height={26} />
            BetterCmdTab
          </motion.h1>
          <motion.p className="tagline" variants={reveal}>
            The Cmd+Tab macOS deserves.
          </motion.p>
          <motion.p className="lede" variants={reveal}>
            A fast, native window switcher for macOS.
            <br />
            Free forever, zero telemetry, no subscription.
          </motion.p>
        </motion.header>

        <Shots />

        <motion.hr
          initial={{ scaleX: 0, opacity: 0 }}
          whileInView={{ scaleX: 1, opacity: 1 }}
          viewport={{ once: true }}
          transition={{ duration: 0.6, ease: EASE }}
          style={{ transformOrigin: "left" }}
        />

        <motion.section {...inView}>
          <motion.h2 variants={reveal}>Download</motion.h2>
          <motion.p className="row" variants={reveal}>
            <motion.a
              className="cta"
              href={dmgUrl}
              download
              whileHover={{ y: -1 }}
              whileTap={{ y: 0 }}
            >
              ↓ Download .dmg
            </motion.a>
            <span className="muted">
              {version ? `${version} · ` : ""}macOS 13.0+ · Apple Silicon &amp; Intel
            </span>
          </motion.p>
        </motion.section>

        <motion.section {...inView}>
          <motion.h2 variants={reveal}>Features</motion.h2>
          <Rows rows={features} />
        </motion.section>

        <motion.section {...inView}>
          <motion.h2 variants={reveal}>Shortcuts</motion.h2>
          <Rows rows={shortcuts} combo />
          <motion.p className="muted note" variants={reveal}>
            Hold Cmd, tap to step through, release to activate.
          </motion.p>
        </motion.section>

        <motion.section {...inView}>
          <motion.h2 variants={reveal}>Connect</motion.h2>
          <motion.p className="links" variants={reveal}>
            <a href={REPO}>GitHub</a>
            <span className="sep">·</span>
            <a href={`${REPO}/releases`}>Releases</a>
            <span className="sep">·</span>
            <a href={`${REPO}/blob/main/LICENSE`}>License</a>
          </motion.p>
        </motion.section>

        <motion.footer
          initial={{ opacity: 0 }}
          whileInView={{ opacity: 1 }}
          viewport={{ once: true }}
          transition={{ duration: 0.5 }}
        >
          Built by <a href="https://github.com/rokartur">@rokartur</a> · GPL v3
        </motion.footer>
      </main>
    </MotionConfig>
  );
}
