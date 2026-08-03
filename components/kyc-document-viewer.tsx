"use client";

import { useState } from "react";
import { Eye, X, ExternalLink } from "lucide-react";
import { Button } from "@/components/ui/button";

type Doc = { label: string; url: string | null };

export function KycDocumentViewer({
  frontUrl,
  backUrl,
  selfieUrl,
}: {
  frontUrl: string | null;
  backUrl: string | null;
  selfieUrl: string | null;
}) {
  const [open, setOpen] = useState(false);
  const [lightbox, setLightbox] = useState<string | null>(null);

  const docs: Doc[] = [
    { label: "ID Front", url: frontUrl },
    { label: "ID Back", url: backUrl },
    { label: "Selfie", url: selfieUrl },
  ].filter((d) => d.url);

  if (!docs.length) {
    return <p className="text-xs text-ink-400 italic">No documents uploaded.</p>;
  }

  return (
    <div>
      <Button size="sm" variant="outline" onClick={() => setOpen((v) => !v)}>
        <Eye className="mr-1.5 h-3.5 w-3.5" />
        {open ? "Hide documents" : `View documents (${docs.length})`}
      </Button>

      {open && (
        <div className="mt-3 flex flex-wrap gap-3">
          {docs.map((doc) => (
            <div key={doc.label} className="flex flex-col gap-1">
              <p className="text-xs font-medium text-ink-500">{doc.label}</p>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={doc.url!}
                alt={doc.label}
                className="h-32 w-44 cursor-zoom-in rounded-md border border-paper-200 object-cover shadow-sm transition-transform hover:scale-105"
                onClick={() => setLightbox(doc.url)}
              />
              <a
                href={doc.url!}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-1 text-xs text-ink-500 hover:text-ink-900"
              >
                <ExternalLink className="h-3 w-3" /> Open original
              </a>
            </div>
          ))}
        </div>
      )}

      {/* Lightbox overlay */}
      {lightbox && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/80 p-4"
          onClick={() => setLightbox(null)}
        >
          <button
            className="absolute right-4 top-4 rounded-full bg-white/20 p-2 text-white hover:bg-white/30"
            onClick={() => setLightbox(null)}
          >
            <X className="h-5 w-5" />
          </button>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={lightbox}
            alt="Document preview"
            className="max-h-[90vh] max-w-[90vw] rounded-lg object-contain shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          />
        </div>
      )}
    </div>
  );
}
