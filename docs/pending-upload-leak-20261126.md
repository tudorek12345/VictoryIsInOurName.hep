# Pending upload ownership, 26 November

The thin command recorder allocated an upload, boxed its owner and wrote that
pointer into a command packet. A worker normally recovered ownership when it
translated the packet. Resetting or dropping a list before its pending words
were handed over instead cleared the words without destroying the upload owner.

On Windows, the default upload allocator uses reusable low-address arena blocks.
Missing destruction leaves those blocks marked busy; the fallback allocator can
also retain its vector allocation. The corrected `Front::leave` walks only its
own pending packet boundaries and destroys upload owners exactly once. It never
walks arbitrary payload words as opcodes or frees handed-over worker allocations.
Malformed bounds stop ownership interpretation. GPU submission retirement and
the arena's address-reservation policy are unchanged.

Six new authored tests cover actual allocation, reset, list destruction, repeated
discard, worker handover, payload framing and malformed packets. A test-only
per-object drop observer proves exact ownership without relying on a freed
address that another test could reuse. The three real discard-path tests failed
against the original behavior with destructor count zero instead of one. All six
passed with the correction, as did three existing thin-list and two existing
upload tests. Tests used WARP, one compiler job and no submitted GPU work from
the authored cases. The test-build memory floor did not trigger; observed free
physical RAM stayed above 14.5 GiB. Independent source/test review found no
remaining blocker before execution.

This is a confirmed allocation leak, **not an explanation of the whole memory
failure**. The earlier `7397c202` title run created four 4 MiB upload arenas,
16 MiB in total. Reusing their blocks does not imply immediate release of their
address reservations or a multi-gigabyte private-memory reduction. A new thin
recorder diagnostic reports pending uploads reclaimed per frame, not bytes.

The separate internal command-list pool can retain previously used allocator
capacity without a count or byte bound. Its measured contribution remains
unknown; no speculative pool flush or shortened GPU retirement was included.
Static buffer-descriptor ownership similarly requires lifetime evidence before
eviction. The optional mapped-VRAM buffer path remains off: placement in VRAM
does not establish an equal reduction in Windows job commit.

The source-only patch is
[victory-pending-upload-reclamation.patch](../runtimes/patches/victory-pending-upload-reclamation.patch).
It follows `988ed8f`, producing active source `8f6f742`. Its files are outside the
translator cache fingerprint. The rebuilt executable still requires its own
successful guarded cache validation and title run before a runtime improvement
can be claimed.
