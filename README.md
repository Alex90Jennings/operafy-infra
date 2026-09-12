<div align="center">

# operafy-infra

**The media delivery infrastructure for [Operafy](https://operafy-music.vercel.app), written in Terraform.**

![Terraform](https://img.shields.io/badge/Terraform-1.16-7B42BC?style=flat-square&logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-S3_·_CloudFront_·_ACM_·_IAM-FF9900?style=flat-square&logo=amazonwebservices&logoColor=white)
![OIDC](https://img.shields.io/badge/GitHub_OIDC-no_stored_keys-2088FF?style=flat-square&logo=github&logoColor=white)

</div>

---

## Why this exists

Operafy streams historic opera recordings. Until now it hotlinked them straight from
Wikimedia Commons, which works right up until it doesn't: it is someone else's bandwidth, someone
else's uptime, and a URL that can change without warning and take the player down with it.

This repository is the fix. A private S3 bucket holds the media, CloudFront serves it from the edge,
and the bucket is readable by that one distribution and nothing else.

It is deliberately small. The interesting part is not the resource count, it is that every choice
below has a reason attached to it.

---

## What it builds

```
                    ┌──────────────┐
   viewer  ───────► │  CloudFront  │  TLS, compression, edge cache
                    └──────┬───────┘
                           │  signed with SigV4 via Origin Access Control
                    ┌──────▼───────┐
                    │  S3 (private)│  versioned, encrypted, lifecycle swept
                    └──────────────┘
```

| Resource | Why |
| :-- | :-- |
| **S3 bucket** | Private. Public access blocked at the account level as well as the policy, so a careless future change cannot open it. |
| **Versioning + lifecycle** | Versioning protects against a bad sync overwriting good media. A lifecycle rule expires superseded versions after 30 days, because versioning without expiry is a slow leak that bills forever. |
| **Origin Access Control** | The modern replacement for Origin Access Identity. The bucket policy names this exact distribution by `SourceArn`, so it is not "any CloudFront can read this". |
| **HTTPS-only bucket policy** | An explicit `Deny` on `aws:SecureTransport = false`, so plaintext requests are refused rather than merely discouraged. |
| **CloudFront distribution** | HTTP/2 and HTTP/3, compression on, `GET`/`HEAD`/`OPTIONS` only. Read-only media has no business accepting a `PUT`. |
| **Managed cache policies** | `CachingOptimized`, `CORS-S3Origin` and `SecurityHeadersPolicy`. AWS keeps them current; a hand rolled copy would rot. |
| **ACM certificate** | Optional. Issued in `us-east-1` because that is the only region CloudFront reads certificates from. Skipped entirely when no custom domain is set. |
| **IAM role for GitHub** | Optional. Trusts GitHub's OIDC provider, scoped to one repository, and may only sync this bucket and invalidate this distribution. |

---

## The guard rail worth copying

This machine holds credentials for more than one AWS account, and one of them is production. A wrong
`AWS_PROFILE` is a very cheap mistake to make and a very expensive one to explain, so the provider
refuses to run anywhere unexpected:

```hcl
provider "aws" {
  allowed_account_ids = [var.aws_account_id]
}
```

Terraform now aborts before touching anything if the credentials resolve to a different account.
It costs one line.

---

## State

State lives in its own S3 bucket, versioned and encrypted, with locking handled by a **native S3 lock
file** rather than a DynamoDB table. Terraform 1.10 added this, and it removes a whole resource
whose only job was to hold a lock.

The state bucket cannot store its own state, so it is created once by a small separate config:

```bash
cd bootstrap
terraform init
terraform apply -var aws_account_id=<account>
```

It is marked `prevent_destroy`, because state is the one thing here that cannot be rebuilt from
source.

---

## Running it

```bash
cp terraform.tfvars.example terraform.tfvars   # fill in the account id
terraform init -backend-config="bucket=operafy-tfstate-<account>"
terraform plan
terraform apply
```

Then upload the media and invalidate the cache:

```bash
./scripts/sync-media.sh ./media
```

Objects are uploaded with `max-age=31536000, immutable`, which is safe because a changed file gets a
changed name.

---

## The pipeline

| Trigger | What runs |
| :-- | :-- |
| **Every push and PR** | `terraform fmt -check`, `init`, `validate` |
| **Every PR** | `terraform plan`, posted back as a PR comment and updated in place on each push |
| **Merge to `main`** | The **reviewed plan artefact** is applied, behind a GitHub environment that requires approval |

Applying a saved plan rather than re-planning at apply time means what was reviewed is exactly what
runs. CI authenticates with GitHub OIDC and a short lived role session, so there is no AWS access key
in this repository or in its secrets.

### The subject claim, which cost an hour

Every role assumption was refused with `Not authorized to perform sts:AssumeRoleWithWebIdentity`,
while the provider, the audience and the trust policy all looked correct. CloudTrail redacts the
request parameters when the call fails authorisation, so it could not say why.

Printing the token's own claims from inside a throwaway workflow gave the answer immediately:

```
sub: repo:Alex90Jennings@97463171/operafy-infra@1367497483:ref:refs/heads/main
```

This account has OIDC **subject customisation** enabled, so the claim carries the numeric owner and
repository IDs. The documented `repo:owner/name:*` pattern never matches, and no amount of staring at
the trust policy reveals that.

Matching the real claim is the stronger option anyway. Numeric IDs are immutable, so pinning them
means renaming the repository, or giving up the account name, cannot hand this role to whoever
registers the name next. `github_subject_claim` carries the pattern.

**The lesson worth keeping:** when a token is rejected, read the token. Guessing at the policy is
slower and it teaches you nothing.

---

## What it costs

Small, but not zero, and worth knowing before you build it:

| | |
| :-- | :-- |
| S3 storage | about $0.023 per GB per month |
| CloudFront | 1 TB out and 10M requests free every month, then about $0.085 per GB |
| ACM certificate | free |
| State bucket | a few kilobytes, effectively free |
| Requests to S3 | close to zero, because CloudFront absorbs the repeat reads |

Measured rather than estimated: Cost Explorer puts CloudFront at **$0.00** across the last four
months on this account, and S3 at **$0.01 to $0.02**. The media is about 200 MB, so this stack should
stay near a penny a month. `price_class` defaults to `PriceClass_100`, Europe and North America only,
because serving a UK audience from São Paulo edges is paying for reach nobody is using.

---

## What is deliberately not here

- **No DynamoDB lock table.** Native S3 locking replaced it.
- **No Route 53.** DNS for these projects lives at the registrar, and a hosted zone is a real monthly
  charge for something a free DNS provider does equally well at this scale.
- **No modules.** One stack, one environment. Wrapping eight resources in a module abstraction would
  be architecture for its own sake.
