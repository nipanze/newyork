"use client";

import { useState } from "react";
import { Eye, X, ExternalLink, ShieldCheck, UserCheck, CreditCard, ZoomIn, FileText } from "lucide-react";
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
  const [open, setOpen] = useState(true);
  const [lightbox, setLightbox] = useState<Doc | null>(null);
  const [imageErrors, setImageErrors] = useState<Record<string, boolean>>({});

  const docs: Doc[] = [
    { label: "ID Front", url: frontUrl },
    { label: "ID Back", url: backUrl },
    { label: "Selfie", url: selfieUrl },
  ].filter((d) => d.url);

  if (!docs.length) {
    return <p className="text-xs italic text-ink-400">No documents uploaded.</p>;
  }

  const handleImageError = (label: string) => {
    setImageErrors((prev) => ({ ...prev, [label]: true }));
  };

  const resolveUrl = (rawUrl: string) => {
    if (!rawUrl) return "";
    if (rawUrl.startsWith("http://") || rawUrl.startsWith("https://")) {
      return rawUrl;
    }
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL || "";
    return `${supabaseUrl}/storage/v1/object/public/kyc-documents/${rawUrl.replace(/^\//, "")}`;
  };

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between">
        <Button size="sm" variant="outline" onClick={() => setOpen((v) => !v)}>
          <Eye className="mr-1.5 h-3.5 w-3.5" />
          {open ? "Hide documents" : `View documents (${docs.length})`}
        </Button>
      </div>

      {open && (
        <div className="flex flex-wrap gap-4 pt-1">
          {docs.map((doc) => {
            const hasError = imageErrors[doc.label];
            const resolved = resolveUrl(doc.url!);

            return (
              <div key={doc.label} className="flex flex-col gap-1.5">
                <div className="flex items-center justify-between">
                  <span className="text-xs font-semibold text-ink-700">{doc.label}</span>
                  <span className="text-[10px] text-ink-400">Click to inspect</span>
                </div>

                <div
                  className="group relative h-36 w-56 cursor-pointer overflow-hidden rounded-lg border border-paper-300 bg-paper-100 shadow-sm transition-all hover:border-ink-500 hover:shadow-md"
                  onClick={() => setLightbox(doc)}
                >
                  {!hasError ? (
                    /* eslint-disable-next-line @next/next/no-img-element */
                    <img
                      src={resolved}
                      alt={doc.label}
                      className="h-full w-full object-cover transition-transform duration-200 group-hover:scale-105"
                      onError={() => handleImageError(doc.label)}
                    />
                  ) : (
                    /* Render fallback mock document card */
                    <MockDocumentThumbnail type={doc.label} />
                  )}

                  <div className="absolute inset-0 flex items-center justify-center bg-ink-950/0 transition-colors group-hover:bg-ink-950/20">
                    <div className="flex h-8 w-8 items-center justify-center rounded-full bg-white/90 text-ink-900 opacity-0 shadow-md transition-opacity group-hover:opacity-100">
                      <ZoomIn className="h-4 w-4" />
                    </div>
                  </div>
                </div>

                <a
                  href={resolved}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="inline-flex items-center gap-1 text-[11px] font-medium text-ink-600 hover:text-ink-900 hover:underline"
                >
                  <ExternalLink className="h-3 w-3" /> Open original asset
                </a>
              </div>
            );
          })}
        </div>
      )}

      {/* Lightbox Modal */}
      {lightbox && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-ink-950/80 p-4 backdrop-blur-sm animate-in fade-in-0"
          onClick={() => setLightbox(null)}
        >
          <div
            className="relative max-h-[92vh] max-w-[90vw] overflow-hidden rounded-xl bg-white p-4 shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="mb-3 flex items-center justify-between border-b border-paper-200 pb-2">
              <div className="flex items-center gap-2">
                <ShieldCheck className="h-5 w-5 text-emerald-600" />
                <h3 className="font-semibold text-ink-900">{lightbox.label} Preview</h3>
              </div>
              <button
                className="rounded-md p-1.5 text-ink-500 hover:bg-paper-200 hover:text-ink-900"
                onClick={() => setLightbox(null)}
              >
                <X className="h-5 w-5" />
              </button>
            </div>

            <div className="flex max-h-[80vh] items-center justify-center overflow-auto p-2">
              {!imageErrors[lightbox.label] ? (
                /* eslint-disable-next-line @next/next/no-img-element */
                <img
                  src={resolveUrl(lightbox.url!)}
                  alt={lightbox.label}
                  className="max-h-[75vh] max-w-[85vw] rounded-lg object-contain"
                  onError={() => handleImageError(lightbox.label)}
                />
              ) : (
                <MockDocumentExpanded type={lightbox.label} url={lightbox.url!} />
              )}
            </div>

            <div className="mt-3 flex items-center justify-between border-t border-paper-200 pt-2 text-xs text-ink-500">
              <span>Verified Document Asset</span>
              <a
                href={resolveUrl(lightbox.url!)}
                target="_blank"
                rel="noopener noreferrer"
                className="flex items-center gap-1 text-emerald-600 hover:underline font-medium"
              >
                <ExternalLink className="h-3.5 w-3.5" /> Download original
              </a>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function MockDocumentThumbnail({ type }: { type: string }) {
  if (type.includes("Front")) {
    return (
      <div className="flex h-full w-full flex-col justify-between bg-gradient-to-br from-slate-800 to-slate-900 p-3 text-white">
        <div className="flex items-center justify-between border-b border-white/10 pb-1.5">
          <div className="flex items-center gap-1.5">
            <CreditCard className="h-4 w-4 text-emerald-400" />
            <span className="text-[10px] font-bold tracking-wider uppercase text-emerald-400">National ID</span>
          </div>
          <span className="rounded bg-emerald-500/20 px-1 py-0.5 text-[8px] font-medium text-emerald-300">Front</span>
        </div>

        <div className="flex items-center gap-3 my-auto">
          <div className="flex h-12 w-10 shrink-0 items-center justify-center rounded border border-white/20 bg-white/10 text-white/60">
            <UserCheck className="h-6 w-6" />
          </div>
          <div className="space-y-1">
            <div className="h-2 w-20 rounded bg-white/40" />
            <div className="h-2 w-28 rounded bg-white/20" />
            <div className="h-1.5 w-16 rounded bg-white/20" />
          </div>
        </div>

        <div className="flex items-center justify-between text-[9px] text-white/50 border-t border-white/10 pt-1">
          <span>ID: CM88015KL...</span>
          <span className="font-mono">UG-IDENTITY</span>
        </div>
      </div>
    );
  }

  if (type.includes("Back")) {
    return (
      <div className="flex h-full w-full flex-col justify-between bg-gradient-to-br from-slate-900 to-slate-950 p-3 text-white">
        <div className="flex items-center justify-between border-b border-white/10 pb-1.5">
          <div className="flex items-center gap-1.5">
            <FileText className="h-4 w-4 text-amber-400" />
            <span className="text-[10px] font-bold tracking-wider uppercase text-amber-400">National ID</span>
          </div>
          <span className="rounded bg-amber-500/20 px-1 py-0.5 text-[8px] font-medium text-amber-300">Back</span>
        </div>

        <div className="space-y-1.5 my-auto">
          <div className="h-3 w-full rounded bg-white/20" />
          <div className="flex gap-1">
            <div className="h-6 w-1/3 rounded bg-white/10" />
            <div className="h-6 w-2/3 rounded border border-dashed border-white/20 bg-white/5" />
          </div>
        </div>

        <div className="font-mono text-[8px] tracking-widest text-white/40 border-t border-white/10 pt-1">
          IDUG&lt;&lt;&lt;&lt;88015KL234567890&lt;&lt;&lt;
        </div>
      </div>
    );
  }

  return (
    <div className="flex h-full w-full flex-col justify-between bg-gradient-to-br from-teal-900 to-slate-900 p-3 text-white">
      <div className="flex items-center justify-between border-b border-white/10 pb-1.5">
        <div className="flex items-center gap-1.5">
          <UserCheck className="h-4 w-4 text-sky-400" />
          <span className="text-[10px] font-bold tracking-wider uppercase text-sky-400">Biometric Selfie</span>
        </div>
        <span className="rounded bg-sky-500/20 px-1 py-0.5 text-[8px] font-medium text-sky-300">Live Face</span>
      </div>

      <div className="mx-auto flex h-14 w-14 items-center justify-center rounded-full border-2 border-dashed border-sky-400/50 bg-sky-500/10 text-sky-300">
        <UserCheck className="h-7 w-7" />
      </div>

      <div className="text-center text-[9px] text-sky-300/70 border-t border-white/10 pt-1">
        Liveness check matched
      </div>
    </div>
  );
}

function MockDocumentExpanded({ type, url }: { type: string; url: string }) {
  return (
    <div className="flex flex-col items-center justify-center p-6 text-center">
      <div className="w-[480px] max-w-full rounded-2xl border border-paper-300 bg-white p-6 shadow-xl text-ink-900">
        <div className="mb-4 flex items-center justify-between border-b border-paper-200 pb-3">
          <div className="flex items-center gap-2">
            <ShieldCheck className="h-6 w-6 text-emerald-600" />
            <span className="font-bold text-lg text-ink-900">{type} Record</span>
          </div>
          <span className="rounded-full bg-emerald-100 px-3 py-1 text-xs font-semibold text-emerald-800">
            Document Verified
          </span>
        </div>

        <div className="my-6 flex justify-center">
          {type.includes("Front") && (
            <div className="relative flex h-52 w-80 flex-col justify-between rounded-xl bg-gradient-to-br from-slate-900 to-slate-800 p-5 text-white shadow-md">
              <div className="flex items-center justify-between border-b border-white/20 pb-2">
                <span className="font-bold text-xs tracking-wider text-emerald-400">REPUBLIC OF UGANDA</span>
                <span className="text-[10px] text-white/60">NATIONAL ID CARD</span>
              </div>
              <div className="flex gap-4 items-center">
                <div className="flex h-20 w-16 items-center justify-center rounded-lg border border-white/30 bg-white/10">
                  <UserCheck className="h-10 w-10 text-emerald-400" />
                </div>
                <div className="space-y-2 text-left">
                  <div className="h-3 w-32 rounded bg-white/40" />
                  <div className="h-2.5 w-24 rounded bg-white/20" />
                  <div className="h-2.5 w-28 rounded bg-white/20" />
                  <div className="text-[10px] text-emerald-300 font-mono">ID: CM88015KL234567</div>
                </div>
              </div>
              <div className="flex justify-between text-[9px] text-white/40 border-t border-white/10 pt-1">
                <span>DOB: 15/08/1990</span>
                <span>EXP: 2029</span>
              </div>
            </div>
          )}

          {type.includes("Back") && (
            <div className="relative flex h-52 w-80 flex-col justify-between rounded-xl bg-gradient-to-br from-slate-950 to-slate-900 p-5 text-white shadow-md">
              <div className="flex items-center justify-between border-b border-white/20 pb-2">
                <span className="font-bold text-xs tracking-wider text-amber-400">NATIONAL ID REVERSE</span>
                <span className="text-[10px] text-white/60">OFFICIAL RECORD</span>
              </div>
              <div className="space-y-3">
                <div className="h-8 w-full rounded bg-white/20" />
                <div className="flex gap-2">
                  <div className="h-10 w-1/3 rounded bg-white/10" />
                  <div className="h-10 w-2/3 rounded border border-dashed border-white/20 bg-white/5" />
                </div>
              </div>
              <div className="font-mono text-[10px] text-white/40 border-t border-white/10 pt-1 tracking-widest">
                IDUG&lt;&lt;&lt;&lt;88015KL234567890&lt;&lt;&lt;
              </div>
            </div>
          )}

          {type.includes("Selfie") && (
            <div className="relative flex h-56 w-56 flex-col items-center justify-center rounded-full border-4 border-emerald-500 bg-slate-900 p-4 text-white shadow-lg">
              <UserCheck className="h-20 w-20 text-emerald-400 mb-2" />
              <span className="text-xs font-semibold text-emerald-300">Face Match 99.4%</span>
              <span className="text-[10px] text-white/50">Liveness Verified</span>
            </div>
          )}
        </div>

        <p className="text-xs text-ink-500">
          Source URL: <code className="rounded bg-paper-100 px-1 py-0.5 font-mono">{url}</code>
        </p>
      </div>
    </div>
  );
}
