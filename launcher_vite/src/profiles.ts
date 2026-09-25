export type Profile = {
  id: 'vanilla' | 'enhanced' | 'contra-x'
  name: string
  kicker: string
  version: string
  author: string
  description: string
  hero: string
  remoteFallbacks: string[]
  sourceUrl: string
  accent: string
}

export const profiles: Profile[] = [
  {
    id: 'vanilla',
    name: 'Zero Hour',
    kicker: 'Original game',
    version: '1.04',
    author: 'EA Los Angeles',
    description:
      'The original Zero Hour experience. Clean 1.04 profile with no gameplay mod overlay.',
    hero: './posters/zero-hour.jpg',
    remoteFallbacks: [
      'https://media.moddb.com/images/games/1/1/184/cc_generals_01.jpg',
      'https://images.steamusercontent.com/ugc/2466356199627429300/D2AC5A3B0F49F9A84A3278B540E0096CAA74DC61/?ima=fit&imw=1600',
    ],
    sourceUrl: 'https://www.moddb.com/games/cc-generals-zero-hour',
    accent: '#e7a13a',
  },
  {
    id: 'enhanced',
    name: 'Zero Hour Enhanced',
    kicker: 'Modernized overhaul',
    version: '1.0.0a + 28/03/2024 patch',
    author: 'Acoustic Alpha / VectorIV',
    description:
      'A large-scale gameplay and visual overhaul with reworked units, environments, effects, terrain, balance and quality-of-life changes.',
    hero: './posters/enhanced.jpg',
    remoteFallbacks: [
      'https://media.moddb.com/images/mods/1/17/16856/comp1.jpg',
      'https://media.moddb.com/images/downloads/1/89/88037/Enhanced_New_Install_V.jpg',
    ],
    sourceUrl: 'https://www.moddb.com/mods/cc-generals-zero-hour-enhanced',
    accent: '#f0b64d',
  },
  {
    id: 'contra-x',
    name: 'Contra X',
    kicker: 'Total conversion',
    version: 'Beta 2 + Patch 1',
    author: 'Contra Mod Team',
    description:
      'The current Contra X branch with new models, structures, weapons, effects, balance changes and its own strong visual identity.',
    hero: './posters/contra-x.jpg',
    remoteFallbacks: [
      'https://media.moddb.com/images/members/1/292/291992/profile/Contra_X_Beta_2_Banner_For_Artic.jpg',
      'https://media.moddb.com/images/downloads/1/64/63773/Install_Final.jpg',
    ],
    sourceUrl: 'https://www.moddb.com/mods/contra',
    accent: '#e15b42',
  },
]
