import { mkdir, stat, writeFile } from 'node:fs/promises'
import { dirname, resolve } from 'node:path'

const root = resolve(process.cwd(), 'public/posters')

const posters = [
  {
    file: 'zero-hour.jpg',
    urls: [
      'https://media.moddb.com/images/games/1/1/184/cc_generals_01.jpg',
      'https://images.steamusercontent.com/ugc/2466356199627429300/D2AC5A3B0F49F9A84A3278B540E0096CAA74DC61/?ima=fit&imw=1600',
    ],
  },
  {
    file: 'enhanced.jpg',
    urls: [
      'https://media.moddb.com/images/mods/1/17/16856/comp1.jpg',
      'https://media.moddb.com/images/downloads/1/89/88037/Enhanced_New_Install_V.jpg',
    ],
  },
  {
    file: 'contra-x.jpg',
    urls: [
      'https://media.moddb.com/images/members/1/292/291992/profile/Contra_X_Beta_2_Banner_For_Artic.jpg',
      'https://media.moddb.com/images/downloads/1/64/63773/Install_Final.jpg',
    ],
  },
]

async function exists(path) {
  try {
    const info = await stat(path)
    return info.size > 20_000
  } catch {
    return false
  }
}

async function fetchPoster(target, urls) {
  if (await exists(target)) {
    console.log('poster cached:', target)
    return
  }

  for (const url of urls) {
    try {
      console.log('downloading:', url)
      const response = await fetch(url, {
        redirect: 'follow',
        headers: {
          'user-agent': 'Mozilla/5.0 ZeroHourLauncher/1.0',
          referer: 'https://www.moddb.com/',
          accept: 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
        },
      })

      if (!response.ok) {
        console.warn('failed:', response.status, url)
        continue
      }

      const contentType = response.headers.get('content-type') ?? ''
      if (!contentType.startsWith('image/')) {
        console.warn('not an image:', contentType, url)
        continue
      }

      const buffer = Buffer.from(await response.arrayBuffer())
      if (buffer.length < 20_000) {
        console.warn('image too small:', buffer.length, url)
        continue
      }

      await mkdir(dirname(target), { recursive: true })
      await writeFile(target, buffer)
      console.log('saved:', target, buffer.length, 'bytes')
      return
    } catch (error) {
      console.warn('download error:', url, error instanceof Error ? error.message : error)
    }
  }

  console.warn('No poster source succeeded for', target, '- runtime fallback will be used.')
}

await mkdir(root, { recursive: true })

for (const poster of posters) {
  await fetchPoster(resolve(root, poster.file), poster.urls)
}
