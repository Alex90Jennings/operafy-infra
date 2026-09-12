#!/usr/bin/env bash
# Sync a local media directory to the bucket and invalidate the CDN.
#
#   ./scripts/sync-media.sh ./media
#
# Immutable assets get a long max-age: the CDN and the browser can hold them
# for a year because a changed file gets a changed name.
set -euo pipefail

SRC="${1:-./media}"

if [[ ! -d "$SRC" ]]; then
  echo "error: '$SRC' is not a directory" >&2
  exit 1
fi

BUCKET="$(terraform output -raw bucket_name)"
DISTRIBUTION="$(terraform output -raw distribution_id)"

echo "Syncing $SRC to s3://$BUCKET"
aws s3 sync "$SRC" "s3://$BUCKET" \
  --delete \
  --cache-control "public, max-age=31536000, immutable"

echo "Invalidating $DISTRIBUTION"
aws cloudfront create-invalidation \
  --distribution-id "$DISTRIBUTION" \
  --paths "/*" \
  --query 'Invalidation.Id' \
  --output text

echo "Done. Media is live at $(terraform output -raw cdn_url)"
