# Changelog

## [1.1.0](https://github.com/ithaca-lab-org/idp-gitops/compare/v1.0.0...v1.1.0) (2026-10-30)


### Features

* **argocd:** private Argo CD UI on the tailnet ([#23](https://github.com/ithaca-lab-org/idp-gitops/issues/23)) ([c29beb3](https://github.com/ithaca-lab-org/idp-gitops/commit/c29beb3eb792858cb1b3b03977faec0fd81c234f))
* **identity:** lldap, Keycloak and Keycloak Postgres (waves 8-9) ([#6](https://github.com/ithaca-lab-org/idp-gitops/issues/6)) ([88dd496](https://github.com/ithaca-lab-org/idp-gitops/commit/88dd4964536172987ec87ca9ddbfba74e78e092f))
* **identity:** seed lldap with the dev groups and users on every rebuild ([#21](https://github.com/ithaca-lab-org/idp-gitops/issues/21)) ([cff9688](https://github.com/ithaca-lab-org/idp-gitops/commit/cff968861e8fc1063eb36d8cd332be1ce73b2ab5))
* **keycloak:** set the master realm Frontend URL to the tailnet admin host ([#12](https://github.com/ithaca-lab-org/idp-gitops/issues/12)) ([8f46940](https://github.com/ithaca-lab-org/idp-gitops/commit/8f46940c1d8a84b63e93d5977374589e363d9309))
* **operator:** deploy the TeamNamespace operator as wave 12 ([#18](https://github.com/ithaca-lab-org/idp-gitops/issues/18)) ([db6336a](https://github.com/ithaca-lab-org/idp-gitops/commit/db6336adeaef1a362c5fcdeea8afacd9c3ed7d1d))
* **portal:** deploy portal-api behind the ingress at portal.apps (wave 11) ([#17](https://github.com/ithaca-lab-org/idp-gitops/issues/17)) ([8881e20](https://github.com/ithaca-lab-org/idp-gitops/commit/8881e2073d54fbcac1b2f8cada3366f94503375a))
* **portal:** enable the Secrets page (SECRETS_ENABLED=true) ([#30](https://github.com/ithaca-lab-org/idp-gitops/issues/30)) ([27a646e](https://github.com/ithaca-lab-org/idp-gitops/commit/27a646e5ad9fbb970d6643b4e10027531f447aed))
* **portal:** MongoDB, portal RBAC and order settings for the order API ([#19](https://github.com/ithaca-lab-org/idp-gitops/issues/19)) ([beeaf22](https://github.com/ithaca-lab-org/idp-gitops/commit/beeaf223f15354d107c07a82840db36cc8beec98))
* **portal:** order events publisher and notifier (email off) ([#24](https://github.com/ithaca-lab-org/idp-gitops/issues/24)) ([78da5ba](https://github.com/ithaca-lab-org/idp-gitops/commit/78da5ba37c191ca8e8295c35fa0e06abb9a6cc01))
* **portal:** ship the order API image (1c2c3b92) ([#20](https://github.com/ithaca-lab-org/idp-gitops/issues/20)) ([a811633](https://github.com/ithaca-lab-org/idp-gitops/commit/a8116335e783b7e2533fec910f56734955c61a99))
* **portal:** write-only Vault role and RBAC for the portal Secrets page ([#28](https://github.com/ithaca-lab-org/idp-gitops/issues/28)) ([9a5bdd6](https://github.com/ithaca-lab-org/idp-gitops/commit/9a5bdd672e60503a024521433b075a09eebda658))
* **vault:** per-namespace Vault paths (ns-reader template, ns-purge, shared VaultConnection) ([#26](https://github.com/ithaca-lab-org/idp-gitops/issues/26)) ([17519f2](https://github.com/ithaca-lab-org/idp-gitops/commit/17519f2eef856909ee521e5339557956141251eb))
* **vault:** self-hosted Vault with KMS auto-unseal and VSO demo ([#25](https://github.com/ithaca-lab-org/idp-gitops/issues/25)) ([2547671](https://github.com/ithaca-lab-org/idp-gitops/commit/2547671072f74d22bacff1ad51b944009ede6014))


### Bug Fixes

* **identity:** apply Opus review findings (policy, redirect URIs, admin password) ([#16](https://github.com/ithaca-lab-org/idp-gitops/issues/16)) ([c6e521a](https://github.com/ithaca-lab-org/idp-gitops/commit/c6e521ad6739feb0fa7b1d65ed2aeca6d7ca11fe))
* **identity:** move Tailscale admin Ingresses into their own wave-10 app ([#8](https://github.com/ithaca-lab-org/idp-gitops/issues/8)) ([b962f74](https://github.com/ithaca-lab-org/idp-gitops/commit/b962f74b9c8e643f5e36e9ea552544d21fcb85b1))
* **keycloak:** add the LDAP username mapper to the realm import ([#14](https://github.com/ithaca-lab-org/idp-gitops/issues/14)) ([38e5cc7](https://github.com/ithaca-lab-org/idp-gitops/commit/38e5cc7287a0d604b126556b48af1c9ab43d3635))
* **keycloak:** allow the two static 3rd-party-cookie check pages publicly ([#11](https://github.com/ithaca-lab-org/idp-gitops/issues/11)) ([e5de9c4](https://github.com/ithaca-lab-org/idp-gitops/commit/e5de9c4f015afa93bc9a030f86a28f607283471b))
* **keycloak:** drop duplicate KC_HTTP_ENABLED env var ([#9](https://github.com/ithaca-lab-org/idp-gitops/issues/9)) ([21f60be](https://github.com/ithaca-lab-org/idp-gitops/commit/21f60becd44f42fc03592742a18009ec409b1447))
* **keycloak:** drop ServerSideApply so defaulted route fields are not drift ([#10](https://github.com/ithaca-lab-org/idp-gitops/issues/10)) ([59864a8](https://github.com/ithaca-lab-org/idp-gitops/commit/59864a83b9cfa57d26de4c59c6d812bafccf6e4c))
* **keycloak:** pass kcadm --config after the subcommand and show login errors ([#13](https://github.com/ithaca-lab-org/idp-gitops/issues/13)) ([7c9cca5](https://github.com/ithaca-lab-org/idp-gitops/commit/7c9cca59dba0ecc1d419484124669b15bfda80f3))
* **keycloak:** trust X-Forwarded-* headers from the Istio gateway ([#15](https://github.com/ithaca-lab-org/idp-gitops/issues/15)) ([ca842d3](https://github.com/ithaca-lab-org/idp-gitops/commit/ca842d39a86e38a97befaadd244ddb1e7a00d4ae))
* **vault:** vault-proof Kubernetes-auth role for the proof script ([#31](https://github.com/ithaca-lab-org/idp-gitops/issues/31)) ([920482f](https://github.com/ithaca-lab-org/idp-gitops/commit/920482ff6fc35998cf829eca58d0b80c2241bd09))

## 1.0.0 (2026-10-14)


### Features

* Istio ambient, ingress gateway, Let's Encrypt and echo app (waves 2-7) ([#3](https://github.com/ithaca-lab-org/idp-gitops/issues/3)) ([5933d7b](https://github.com/ithaca-lab-org/idp-gitops/commit/5933d7bcf09870dca54e9c18251b491a42cb82c7))
* Tailscale operator as wave 2 (chart 1.102.4) ([#1](https://github.com/ithaca-lab-org/idp-gitops/issues/1)) ([ddd1bc3](https://github.com/ithaca-lab-org/idp-gitops/commit/ddd1bc3eb1f70d39fb313c7b89982f49184b1f6b))


### Bug Fixes

* **istio:** set cni bin dir explicitly for GKE under Argo CD ([#4](https://github.com/ithaca-lab-org/idp-gitops/issues/4)) ([b6de445](https://github.com/ithaca-lab-org/idp-gitops/commit/b6de44540c643dc3995c3237cd75130f21dd7d63))
* **ztunnel:** ignore API-defaulted resourceFieldRef divisor ([#5](https://github.com/ithaca-lab-org/idp-gitops/issues/5)) ([f8385ba](https://github.com/ithaca-lab-org/idp-gitops/commit/f8385bad8deffef570b7510a95b8c994a5fc472d))
