import { useEffect, useMemo, useState } from 'react'
import { profiles, type Profile } from './profiles'

type SmartImageProps = {
  profile: Profile
  className?: string
  alt?: string
}

function SmartImage({ profile, className, alt }: SmartImageProps) {
  const candidates = useMemo(
    () => [profile.hero, ...profile.remoteFallbacks],
    [profile],
  )
  const [index, setIndex] = useState(0)

  useEffect(() => setIndex(0), [profile.id])

  if (index >= candidates.length) {
    return (
      <div
        className={`${className ?? ''} poster-fallback`}
        style={{ '--accent': profile.accent } as React.CSSProperties}
      >
        <span>{profile.name}</span>
      </div>
    )
  }

  return (
    <img
      className={className}
      src={candidates[index]}
      alt={alt ?? profile.name}
      draggable={false}
      onError={() => setIndex((value) => value + 1)}
    />
  )
}

function App() {
  const [selectedId, setSelectedId] = useState<Profile['id']>('enhanced')
  const [notice, setNotice] = useState('')
  const profile = profiles.find((item) => item.id === selectedId) ?? profiles[0]

  const selectByOffset = (offset: number) => {
    const currentIndex = profiles.findIndex((item) => item.id === selectedId)
    const nextIndex = Math.max(0, Math.min(profiles.length - 1, currentIndex + offset))
    setSelectedId(profiles[nextIndex].id)
  }

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'ArrowUp' || event.key === 'ArrowLeft') {
        selectByOffset(-1)
      }
      if (event.key === 'ArrowDown' || event.key === 'ArrowRight') {
        selectByOffset(1)
      }
      if (event.key === 'Enter') {
        launchProfile()
      }
    }

    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  })

  const launchProfile = () => {
    const bridge = window.webkit?.messageHandlers?.launchProfile
    if (bridge) {
      bridge.postMessage({ profile: profile.id })
      setNotice(`Launching ${profile.name}`)
    } else {
      setNotice(`Preview mode · ${profile.name}`)
    }

    window.setTimeout(() => setNotice(''), 1800)
  }

  return (
    <main
      className="launcher"
      style={{ '--accent': profile.accent } as React.CSSProperties}
    >
      <div className="ambient" aria-hidden="true">
        <SmartImage profile={profile} className="ambient-image" />
      </div>

      <header className="topbar">
        <div className="brand">
          <span className="brand-mark" />
          <strong>ZERO HOUR</strong>
          <span>LAUNCHER</span>
        </div>
        <div className="top-meta">
          <span>3 PROFILES</span>
          <span className="status-dot" />
        </div>
      </header>

      <section className="content">
        <article className="hero">
          <SmartImage profile={profile} className="hero-image" />
          <div className="hero-shade" />
          <div className="hero-top">
            <span className="version-chip">{profile.version}</span>
            <a
              className="source-link"
              href={profile.sourceUrl}
              target="_blank"
              rel="noreferrer"
            >
              MOD PAGE ↗
            </a>
          </div>

          <div className="hero-copy">
            <p className="eyebrow">{profile.kicker}</p>
            <h1>{profile.name}</h1>
            <p className="description">{profile.description}</p>
            <div className="author">
              <span>BY</span>
              {profile.author}
            </div>
          </div>
        </article>

        <aside className="sidebar">
          <div className="sidebar-head">
            <span>SELECT PROFILE</span>
            <span>01 — 03</span>
          </div>

          <div className="profiles">
            {profiles.map((item) => {
              const active = item.id === profile.id
              return (
                <button
                  key={item.id}
                  type="button"
                  className={`profile-card ${active ? 'active' : ''}`}
                  onClick={() => setSelectedId(item.id)}
                  style={{ '--item-accent': item.accent } as React.CSSProperties}
                >
                  <SmartImage profile={item} className="profile-thumb" />
                  <span className="profile-text">
                    <strong>{item.name}</strong>
                    <small>{item.version}</small>
                  </span>
                  <span className="profile-state" />
                </button>
              )
            })}
          </div>

          <div className="sidebar-spacer" />

          <div className="selected-meta">
            <p>{profile.kicker}</p>
            <span>{profile.author}</span>
          </div>

          <button type="button" className="play" onClick={launchProfile}>
            <span className="play-icon">▶</span>
            PLAY
          </button>
        </aside>
      </section>

      <footer className="footer">
        <span>GENERALSX</span>
        <span>
          <i className="footer-dot" /> {profile.name} · {profile.version}
        </span>
      </footer>

      <div className={`toast ${notice ? 'show' : ''}`}>{notice}</div>
    </main>
  )
}

export default App
