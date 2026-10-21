import type { MarkItem } from '../../types'
import Mark from '../mark'
import VibeCheckLink from '../vibe_check_link'

/** An Every article about this kind, or the Vibe Check of a launched model people ranked in it. The server has already checked the link and tagged it. */
export type Take = { tag: 'article' | 'vibe_check'; title: string; item: MarkItem | null; url: string }

/** Link-outs only: the articles and Vibe Checks live on Every's site, so nothing from them is shown or fetched here. */
export default function Takes({ takes }: { takes: Take[] }) {
  return (
    <ul>
      {takes.map(({ tag, title, item, url }) => (
        <li key={url} className="flex flex-wrap items-center gap-x-4 gap-y-1 border-b border-line py-4">
          {item ? <Mark item={item} size="md" /> : <span aria-hidden="true" className="size-9 shrink-0" />}
          <span className="min-w-[9rem] flex-1 font-semibold text-fg">{title}</span>
          <span className="flex w-full items-center justify-between gap-4 pl-[52px] md:w-auto md:pl-0">
            {tag === 'vibe_check' ? (
              <>
                <span className="text-caption text-fg-muted">Sign-in required</span>
                <VibeCheckLink url={url} modelName={title} />
              </>
            ) : (
              <>
                <span className="text-caption text-fg-muted">Article</span>
                <a href={url} target="_blank" rel="noopener noreferrer" aria-label={`Read ${title} on Every`} className="text-link text-sm">
                  Read <span aria-hidden="true">↗</span>
                </a>
              </>
            )}
          </span>
        </li>
      ))}
    </ul>
  )
}
