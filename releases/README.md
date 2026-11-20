# Versioned framework releases

The release inputs are recorded in `framework.env`. Work is developed on
`release/versioned-framework-builds`; the existing `latest` image is retained.

| Track | Tag | Framework | Tools |
| --- | --- | --- | --- |
| Compatibility | `slivka-0.8.3b4-r1` | Existing 0.8.3b4 | Exact published 21 May image |
| Candidate | `slivka-0.8.5b9-rc1` | Source commit `e455b6370b2c9469dd1331be70b5b0e3835646bd` | Inherited from compatibility image |

The compatibility tag is an alias of index
`sha256:34dc4fa708dd353e6c750ea986c91ea4a7aa66e4350d048bc5502f1baccf4040`.
It is not a fresh build. This preserves every tool/package byte on both
architectures. `Dockerfile` also pins 0.8.3b4 for future installer-based builds,
but those builds are not claimed to reproduce this historical image exactly.

`Dockerfile.framework` builds a wheel from the pinned framework source, upgrades
only the framework environment, checks dependency consistency, and writes an
inventory to `/opt/slivka/build-info.json`. New framework dependencies are pinned
in `framework-constraints.txt`. The existing bioinformatics environments, wrapper
scripts, services and JRonn/Jalview patch remain inherited from the baseline.

## Build and test

```sh
./build-framework.sh --platform linux/arm64 --load
docker tag drsasp/slivka-bio@sha256:34dc4fa708dd353e6c750ea986c91ea4a7aa66e4350d048bc5502f1baccf4040 slivka-bio:slivka-0.8.3b4-r1

# Native ARM64: these three services are absent from the baseline distribution.
./test-release-image.sh \
  --allow-missing disembl-1.4 --allow-missing globplot-2.3 \
  --allow-missing tcoffee-13.41.0 \
  slivka-bio:slivka-0.8.3b4-r1 slivka-bio:slivka-0.8.5b9-rc1

python3 test-framework-migration.py \
  slivka-bio:slivka-0.8.3b4-r1 slivka-bio:slivka-0.8.5b9-rc1 \
  --output-dir release-tests/migration-arm64
```

Run the equivalent checks on a native AMD64 host without `--allow-missing`.
Tests refuse images of the wrong architecture. They use uniquely named disposable
containers, networks and volumes, no published ports, and a pinned MongoDB 7.0
image. They do not use the normal application's Compose project or volumes.
The HTTP smoke test submits a real ClustalO job and downloads its result files.
The migration test additionally verifies a historical job after both migrations,
then restores the original database/media backups and verifies rollback.

The test script returns nonzero for any failed API/inventory/service check or
unexpected missing service. Explicitly accepted missing services remain visible
as missing in the JSON report; they are not reported as passing.

## Publish

Commit the recipe and reviewed inputs first. Build/test each architecture, then:

```sh
source releases/framework.env
docker buildx imagetools create --tag "drsasp/slivka-bio:$COMPATIBILITY_TAG" "$COMPATIBILITY_IMAGE"
./build-framework.sh --platform linux/amd64,linux/arm64 \
  --tag "drsasp/slivka-bio:$CANDIDATE_TAG" --push
```

Inspect the published manifests and test them by digest on both native hosts.
Do not overwrite versioned tags with different content. Do not move `latest`,
`dev` or `test` as part of publishing this RC. Promote a tested candidate digest
only in a separate release decision.

## Existing installations: migration and rollback

A new empty installation can select the candidate tag directly. Existing
0.8.3 installations require an explicit migration; changing the image tag alone
does not migrate their database and job storage.

1. Stop accepting submissions, drain existing jobs, and stop all Slivka processes.
2. Back up MongoDB, media (including uploads and job files), service definitions
   and configuration as one consistent set. Retain the original image digest.
3. Test on restored copies first. Migrations update paths in MongoDB and move
   job files; give the migration container the same internal filesystem paths
   and database connectivity used by the application.
4. With the candidate image, run the following commands in the Slivka environment
   against the intended database and media mounts, while the application is stopped:

   ```sh
   slivka migration 1-nested-job-dirs mongodb://mongo:27017 slivka --jobs-dir /opt/slivka/media/jobs
   slivka migration 2-tz-aware-timestamps --from-timezone UTC mongodb://mongo:27017 slivka
   ```

   Use the original server's actual timestamp timezone instead of UTC if it was
   not running in UTC. Do not rerun migrations blindly: there is no automatic
   migration ledger, and timestamp conversion is not generally idempotent.
5. Start the candidate and verify historical jobs, downloads and new submissions.

For rollback, stop the candidate and restore the matching pre-upgrade database
and filesystem backups before starting the compatibility image. Merely changing
the image back does not reverse the data migrations. Jobs submitted after the
backup require separate handling before restoring it.

The image declares `/opt/slivka/services` as a volume. Existing service volumes
can mask image changes; inspect them rather than deleting them or assuming image
updates replace their contents. The candidate intentionally preserves the tool
inventory, including ARM64's missing DisEMBL, GlobPlot and TCoffee. MAFFT is not
part of the installer-selected service set in either track.

These checks cover synthetic local-queue jobs. They do not validate Slurm API
connectivity, production datasets, or every Jalview client interaction.
