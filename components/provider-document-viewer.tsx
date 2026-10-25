"use client";

import { useState, useEffect } from "react";
import { Eye, ExternalLink, FileText, Loader2, AlertCircle } from "lucide-react";
import { Button } from "@/components/ui/button";

export function ProviderDocumentViewer({
  bucket,
  filePath,
  label = "Document",
}: {
  bucket: "provider-evidence" | "verification-documents";
  filePath: string | null;
  label?: string;
}) {
  const [signedUrl, setSignedUrl] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [showModal, setShowModal] = useState(false);

  useEffect(() => {
    if (!filePath) return;

    if (filePath.startsWith("http://") || filePath.startsWith("https://")) {
      setSignedUrl(filePath);
      return;
    }

    let isMounted = true;
    setLoading(true);
    fetch("/api/admin/verifications/signed-url", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ bucket, path: filePath }),
    })
      .then((res) => res.json())
      .then((data) => {
        if (!isMounted) return;
        if (data.signedUrl) {
          setSignedUrl(data.signedUrl);
        } else {
          setError(data.error || "Could not load file URL");
        }
      })
      .catch((err) => {
        if (isMounted) setError(err.message || "Failed to load document");
      })
      .finally(() => {
        if (isMounted) setLoading(false);
      });

    return () => {
      isMounted = false;
    };
  }, [bucket, filePath]);

  if (!filePath) {
    return <span className="text-xs italic text-ink-400">None uploaded</span>;
  }

  const isPdf = filePath.toLowerCase().endsWith(".pdf");

  return (
    <div className="inline-flex items-center gap-2">
      {loading ? (
        <span className="inline-flex items-center gap-1 text-xs text-ink-500">
          <Loader2 className="h-3 w-3 animate-spin" /> Loading URL…
        </span>
      ) : error ? (
        <span className="inline-flex items-center gap-1 text-xs text-clay-alert" title={error}>
          <AlertCircle className="h-3 w-3" /> Error loading
        </span>
      ) : signedUrl ? (
        <>
          <Button
            size="sm"
            variant="outline"
            className="h-7 gap-1 px-2 text-xs"
            onClick={() => setShowModal(true)}
          >
            {isPdf ? <FileText className="h-3 w-3" /> : <Eye className="h-3 w-3" />}
            {label}
          </Button>

          <a
            href={signedUrl}
            target="_blank"
            rel="noopener noreferrer"
            className="text-ink-400 hover:text-ink-700"
            title="Open in new window"
          >
            <ExternalLink className="h-3.5 w-3.5" />
          </a>

          {showModal && (
            <div
              className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
              onClick={() => setShowModal(false)}
            >
              <div
                className="relative max-h-[90vh] max-w-4xl w-full rounded-lg bg-white p-4 shadow-xl overflow-auto"
                onClick={(e) => e.stopPropagation()}
              >
                <div className="flex items-center justify-between pb-3 border-b border-ink-100 mb-3">
                  <h3 className="text-sm font-semibold text-ink-900">{label}</h3>
                  <button
                    onClick={() => setShowModal(false)}
                    className="rounded p-1 text-ink-500 hover:bg-ink-100"
                  >
                    ✕
                  </button>
                </div>

                <div className="flex justify-center min-h-[300px]">
                  {isPdf ? (
                    <iframe
                      src={signedUrl}
                      className="w-full h-[70vh] rounded border border-ink-200"
                      title={label}
                    />
                  ) : (
                    <img
                      src={signedUrl}
                      alt={label}
                      className="max-h-[75vh] w-auto rounded object-contain"
                    />
                  )}
                </div>
              </div>
            </div>
          )}
        </>
      ) : null}
    </div>
  );
}
