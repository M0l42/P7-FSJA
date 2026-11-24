<p align="center">
   <img src="./front/src/favicon.png" width="192px" />
</p>

# MicroCRM

[![CI](https://github.com/M0l42/P7-FSJA/actions/workflows/ci.yml/badge.svg)](https://github.com/M0l42/P7-FSJA/actions/workflows/ci.yml)
[![Quality Gate](https://sonarcloud.io/api/project_badges/measure?project=M0l42_P7-FSJA&metric=alert_status)](https://sonarcloud.io/summary/overall?id=M0l42_P7-FSJA)
[![Security Rating](https://sonarcloud.io/api/project_badges/measure?project=M0l42_P7-FSJA&metric=security_rating)](https://sonarcloud.io/summary/overall?id=M0l42_P7-FSJA)
[![Coverage](https://sonarcloud.io/api/project_badges/measure?project=M0l42_P7-FSJA&metric=coverage)](https://sonarcloud.io/summary/overall?id=M0l42_P7-FSJA)

MicroCRM est une application de démonstration de gestion de la relation client ([CRM](https://fr.wikipedia.org/wiki/Gestion_de_la_relation_client)) : création, édition et consultation de personnes liées à des organisations. Elle sert de support au projet OpenClassrooms *« Mettez en œuvre l'intégration et le déploiement continu d'une application Full-Stack »* (option B, scénario Orion).

Ce dépôt contient l'application et toute sa chaîne CI/CD : build et tests automatiques, analyse SonarQube Cloud, images Docker scannées et publiées, releases versionnées.

![Page d'accueil](./misc/screenshots/screenshot_1.png)
![Édition de la fiche d'un individu](./misc/screenshots/screenshot_2.png)

**Documentation technique complète** (choix, plans de test, de sécurité, de sauvegarde et de mise à jour) : [`docs/documentation-technique.md`](docs/documentation-technique.md).

## Sommaire

- [Organisation du dépôt](#organisation-du-dépôt)
- [Démarrage rapide avec Docker](#démarrage-rapide-avec-docker)
- [Développer sans Docker](#développer-sans-docker)
- [Tests](#tests)
- [Commandes du Makefile](#commandes-du-makefile)
- [Pipeline CI/CD](#pipeline-cicd)
- [Déploiement](#déploiement)
- [Créer une release](#créer-une-release)
- [Sauvegarde et restauration](#sauvegarde-et-restauration)
- [Configuration](#configuration)
- [Sécurité et mises à jour](#sécurité-et-mises-à-jour)

## Organisation du dépôt

```text
.
├── back/                    API REST Spring Boot 4 (Java 17, Gradle)
│   ├── Dockerfile           image de l'API (build Gradle → JRE Temurin 17, utilisateur non root)
│   └── gradle.lockfile      versions de dépendances verrouillées
├── front/                   application web Angular 22
│   ├── Dockerfile           image du front (build Node 22 → Caddy, utilisateur non root)
│   └── Caddyfile            configuration du serveur web
├── docker-compose.yml       application complète (back + front + volume de données)
├── Makefile                 commandes du quotidien
├── sonar-project.properties configuration de l'analyse SonarQube Cloud
├── .trivyignore             vulnérabilités acceptées (vide aujourd'hui ; justification et expiration obligatoires)
├── .github/
│   ├── workflows/ci.yml     intégration continue (build, tests, couverture, SonarQube) + appel de la CD
│   ├── workflows/cd.yml     livraison continue (images, test de fumée, Trivy, publication GHCR)
│   ├── workflows/release.yml release sur tag vX.Y.Z
│   └── dependabot.yml       mises à jour automatiques des dépendances
└── docs/                    documentation technique et captures
```

## Démarrage rapide avec Docker

**Prérequis :** Docker et Docker Compose v2 (`docker compose`), `make`.

```shell
make up
```

- Application : http://localhost:4200
- API : http://localhost:8080

`make up` construit les deux images et démarre l'application. Les données sont conservées dans le volume Docker `microcrm-data`, y compris après `make down` ou un redémarrage. `make ps` affiche l'état de santé des conteneurs, `make logs` leurs logs, `make smoke` vérifie que l'API et le front répondent.

## Développer sans Docker

### Back-end

**Prérequis :** JDK 17 ou plus récent.

```shell
cd back
./gradlew bootRun          # Windows : gradlew.bat bootRun
```

L'API démarre sur http://localhost:8080, avec une base HSQLDB en mémoire et des données de démonstration.

### Front-end

**Prérequis :** Node.js 22 (22.22.3 ou plus récent) ou 24, npm.

```shell
cd front
npm ci
npm start                  # ng serve
```

L'application démarre sur http://localhost:4200 et appelle l'API sur http://localhost:8080.

> Après une modification des dépendances, générer `package-lock.json` avec la même version de npm que la CI (Node 22, npm 10) ; un lock file écrit par une autre version de npm peut être refusé par `npm ci`. Voir la documentation technique, annexe B.

## Tests

```shell
make test        # tout : back + front
make test-back   # back-end : tests JUnit + rapport de couverture JaCoCo (back/build/reports/)
make test-front  # front-end : tests Karma en Chrome headless + couverture (front/coverage/)
```

Les tests du front nécessitent Google Chrome ou Chromium (variable `CHROME_BIN` si le navigateur n'est pas trouvé automatiquement).

## Commandes du Makefile

| Commande | Rôle |
|---|---|
| `make help` | Liste des commandes |
| `make up` | Construire et démarrer l'application |
| `make down` | Arrêter les conteneurs (les données restent sur le volume) |
| `make logs` / `make ps` | Logs des deux services / état et santé des conteneurs |
| `make smoke` | Vérifier que l'API et le front répondent |
| `make build` | Construire les deux images |
| `make test`, `make test-back`, `make test-front` | Lancer les tests |
| `make backup` | Sauvegarder les données dans `backups/` |
| `make restore FILE=…` | Restaurer une sauvegarde dans une base vide |

La CI n'utilise pas `make` : elle appelle directement `./gradlew` et `npm`, pour que chaque étape reste visible dans les logs GitHub Actions.

## Pipeline CI/CD

```text
push / PR / nightly ─► ci.yml : back ─┐
                                front ─┴─► sonar (quality gate) ─► deliver (main uniquement) ─► cd.yml
tag vX.Y.Z ────────► release.yml : tests ─► cd.yml (images X.Y.Z) ─► GitHub Release
```

| Workflow | Déclencheur | Ce qu'il fait |
|---|---|---|
| `ci.yml` | Push, pull request vers `main`, chaque nuit à 03:00 UTC, manuel | Build et tests back et front en parallèle, couverture, `npm audit` (rapport), analyse SonarQube Cloud avec *quality gate*. Sur un push sur `main`, appelle `cd.yml` |
| `cd.yml` | Appelé par `ci.yml` (push sur `main`) ou par `release.yml` | Build des images, test de fumée (`docker compose up --wait` + `curl`, dont un contrôle CORS), scan Trivy (rapport dans l'onglet *Security* + blocage sur vulnérabilité critique corrigeable), publication sur GHCR |
| `release.yml` | Tag `vX.Y.Z` | Vérifie que le commit est sur `main`, relance les tests, publie les images `X.Y.Z`, crée la *GitHub Release* |

**`main` est protégée** : toute modification passe par une pull request, fusionnable seulement si les jobs `back`, `front` et `sonar` sont verts. Chaque run écrit un résumé (tests, couverture, vulnérabilités npm) sur sa page GitHub Actions et publie les rapports HTML en artefacts.

**Relancer le pipeline :** onglet *Actions* → *CI* → *Run workflow*, ou *Re-run jobs* sur un run existant.

## Déploiement

Les images sont publiées sur GitHub Container Registry :

| Image | Tags |
|---|---|
| `ghcr.io/m0l42/microcrm-back` | `X.Y.Z` (releases), `sha-<commit>` et `latest` (branche `main`) |
| `ghcr.io/m0l42/microcrm-front` | idem |

Sur un serveur disposant de Docker, avec ce dépôt (ou seulement `docker-compose.yml` et le `Makefile`) :

```shell
make backup                      # si une version tourne déjà
TAG=1.0.0 docker compose pull
TAG=1.0.0 docker compose up -d
```

**Retour arrière :** relancer les deux dernières commandes avec la version précédente (`TAG=0.2.0`). Les données restent sur le volume.

**HTTPS en production :** donner le nom de domaine au front (`SITE_ADDRESS=crm.example.com`) et publier les ports 80 et 443 ; Caddy obtient et renouvelle le certificat automatiquement.

## Créer une release

Une release est une décision humaine : elle se déclenche en poussant un tag sur un commit de `main`.

```shell
git switch main && git pull
git tag -a v1.0.0 -m "MicroCRM 1.0.0"
git push origin v1.0.0
```

Le workflow `release.yml` publie les images `1.0.0` puis crée la release avec le JAR (`microcrm-back-1.0.0.jar`), le build Angular (`microcrm-front-1.0.0.zip`), les empreintes `SHA256SUMS.txt` et les commandes de déploiement. Si les tests, le test de fumée ou Trivy échouent, aucune release n'est créée.

## Sauvegarde et restauration

```shell
make backup                                          # archive dans backups/microcrm-<date>.tar.gz
make restore FILE=backups/microcrm-<date>.tar.gz     # restaure dans une base vide
```

`make backup` arrête l'API quelques secondes pour copier des fichiers cohérents. `make restore` refuse d'écraser une base existante : pour remplacer des données, arrêter l'application (`docker compose down`) puis supprimer volontairement le volume (`docker volume rm <projet>_microcrm-data`) avant de restaurer. Le dossier `backups/` est exclu de Git (données personnelles). Fréquence recommandée et scénarios d'incident : documentation technique, §7.

## Configuration

| Variable | Service | Valeur par défaut | Rôle |
|---|---|---|---|
| `APP_CORS_ORIGINS` | back | `http://localhost:4200` | Origines autorisées à appeler l'API depuis un navigateur (séparées par des virgules) |
| `SPRING_DATASOURCE_URL` | back | fichiers HSQLDB sur le volume `microcrm-data` | Emplacement de la base |
| `SITE_ADDRESS` | front | `:8080` | Adresse servie par Caddy ; un nom de domaine active le HTTPS automatique |
| `TAG` | les deux | `latest` | Version des images publiées à utiliser |

## Sécurité et mises à jour

- **Secrets :** un seul secret, `SONAR_TOKEN`, stocké dans les *GitHub Secrets* (et les *Dependabot secrets*). La publication sur GHCR utilise le jeton éphémère de chaque job. *Secret scanning* et *push protection* sont activés.
- **Contrôles :** *quality gate* SonarQube sur chaque pull request, scan Trivy bloquant avant toute publication, `npm audit` à chaque CI, dépendances Gradle verrouillées, conteneurs non `root`, actions GitHub tierces épinglées par SHA de commit.
- **Vulnérabilités acceptées :** uniquement dans `.trivyignore`, chacune avec une justification et une date d'expiration (`CVE-AAAA-NNNNN exp:AAAA-MM-JJ`). Aucune aujourd'hui.
- **Mises à jour :** Dependabot propose chaque semaine les mises à jour mineures et les correctifs (npm, Gradle, images Docker, actions GitHub) ; chaque pull request passe la CI. Les montées de version majeures (Angular, Spring Boot, Java, Node) sont planifiées et réalisées pas à pas (documentation technique, §8).
- **Limite connue :** l'API n'a pas d'authentification ; elle ne doit pas être exposée hors d'un réseau interne (documentation technique, §5.2).
