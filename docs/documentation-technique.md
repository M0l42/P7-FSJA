---
title: "Documentation technique – MicroCRM"
author: "Nathan Boukobza"
option: "Option B (Scénario Orion)"
date: "November 2026"
---

# Documentation technique – MicroCRM

| | |
|---|--|
| **Auteur** | Nathan Boukobza |
| **Option choisie** | Option B (Scénario Orion) |
| **Date** | November 2026 |
| **Dépôt** | https://github.com/M0l42/P7-FSJA |

<!--
Mode d'emploi de ce fichier
- Les blocs "> TODO" reprennent les attendus du template OpenClassrooms : à remplacer par le contenu.
- Les commentaires HTML comme celui-ci n'apparaissent pas dans le PDF final.
- Ordre de rédaction (cf. docs/designs/part1-cicd.md) : §1 → plans §4, §5, §3 → mise en œuvre → §2, §5.1, §7, §8, §9.
- §6 (monitoring) : à compléter en partie 2 (stack ELK).
- Cible : 10 à 15 pages en PDF.
-->

## 1. Introduction

### Contexte du projet

Orion utilise en interne **MicroCRM**, une application de gestion de la relation client composée :

- d'une **API REST** Spring Boot (dossier `back/`) qui expose les personnes et les organisations via Spring Data REST, avec une base HSQLDB en mémoire ;
- d'une **application web** Angular (dossier `front/`) qui consomme cette API depuis le navigateur.

Aujourd'hui, la compilation, les tests et le déploiement sont faits à la main. Ce processus est lent, dépend de la personne qui le réalise et laisse passer des erreurs (étape oubliée, version différente d'un poste à l'autre). La direction technique demande une chaîne CI/CD automatisée, avec des contrôles de qualité et de sécurité à chaque étape.

### Objectifs de l'industrialisation

- **Fiabilité** : chaque modification est compilée et testée automatiquement, de la même façon, sur un environnement neutre.
- **Rapidité** : un push suffit pour obtenir un retour (tests, qualité) en quelques minutes ; un tag suffit pour produire une version livrable.
- **Qualité et sécurité** : analyse SonarQube Cloud (bugs, vulnérabilités, couverture), scan des images Docker, aucun secret en clair dans le dépôt.
- **Reproductibilité** : l'application se lance partout avec une seule commande (`docker compose up` ou `make up`).

### Technologies principales

| Outil | Version | Rôle |
|---|---|---|
| Java | 17 (cible de compilation) | Langage du back-end |
| Spring Boot | 3.2.5 | Framework de l'API REST (Spring Data REST, JPA) |
| HSQLDB | gérée par Spring Boot | Base de données en mémoire |
| Gradle (wrapper) | 8.7 | Build, tests et packaging du back-end |
| Node.js | 22 LTS | Environnement de build du front-end (CI et image Docker) |
| Angular / Angular CLI | 17.3.8 / 17.3.7 | Framework et outillage du front-end |
| TypeScript | 5.4 | Langage du front-end |
| Karma / Jasmine | 6.4 / 5.1 | Tests unitaires du front-end (Chrome headless) |
| Caddy | image officielle | Serveur web du front-end dans le conteneur |
| Docker / Docker Compose | 29.1 / 2.40 (poste local) | Conteneurisation et orchestration locale |
| GitHub Actions | — | Exécution du pipeline CI/CD |
| SonarQube Cloud | — | Analyse de qualité et de sécurité du code |
| GitHub Container Registry | — | Hébergement des images Docker |

Le sujet mentionne Maven ; le projet utilise **Gradle**. Nous conservons Gradle : changer d'outil de build ajouterait un risque sans bénéfice, et Gradle s'intègre aussi bien à GitHub Actions et à SonarQube.

### État initial : analyse locale (étape 1)

Avant toute modification, les builds et les tests existants ont été lancés en local (Java 21.0.5, Node 24.22, npm 11.19, Docker 29.1, Chrome 155).

| Vérification | Résultat |
|---|---|
| `./gradlew build test` (back) | ✅ 2 tests sur 2 réussis (`contextLoads`, `whenFindByEmail_thenReturnPerson`), environ 27 s |
| `npm ci` (front) | ✅ environ 23 s, mais **90 vulnérabilités** signalées par npm (5 critiques, 51 élevées) |
| `ng test` en Chrome headless (front) | ✅ 8 tests sur 8 réussis ; couverture : 31 % des lignes, 9,5 % des branches |
| `ng build` (front) | ✅ bundle initial de 312 kB (83 kB compressé) |
| Image Docker `back` | ✅ 373 Mo, seulement après correction du droit d'exécution de `gradlew` |
| Image Docker `front` | ✅ 78 Mo |
| Application en conteneurs | ✅ API sur `:8080` (`/persons`, `/organizations`), front servi en HTTPS |

Points relevés, traités dans la suite du projet :

1. **`back/gradlew` n'était pas exécutable dans Git** (mode `100644`) : `./gradlew` et le build Docker échouaient avec « Permission denied ». Le même échec se serait produit sur les runners GitHub Actions. Corrigé par `git update-index --chmod=+x back/gradlew`.
2. **Les deux conteneurs tournent en `root`** : les nouveaux Dockerfiles utiliseront un utilisateur non privilégié (§3.1, §5).
3. **Versions Java incohérentes** : compilation en Java 17, mais exécution sur un JRE 21 dans l'image existante.
4. **Version de Node** : Angular 17 ne supporte officiellement que Node 18 et 20, tous deux en fin de vie (Node 20 depuis le 30/04/2026). La CI et le Dockerfile utilisent **Node 22 LTS**, maintenu jusqu'en avril 2027 : c'est une version au-dessus de la liste officielle d'Angular 17, mais la CI vérifie à chaque exécution que le build et les tests fonctionnent. La montée de version d'Angular, qui rétablit un support officiel, relève du plan de mise à jour (§8).
5. **Dépendances npm vulnérables et couverture de tests faible** : à suivre dans SonarQube (§5.1) et dans le plan de remédiation (§5.3).
6. **Dockerfile racine unique à cinq cibles** : base `alpine:3.19` en fin de vie, `FROM node` sans version, `EXPOSE 4200` sur le back-end alors que l'API écoute sur 8080. Il sera remplacé par un Dockerfile par composant (§3.1).

### Présentation rapide du pipeline CI/CD mis en place

```text
 push / pull request / nightly           push sur main                 tag vX.Y.Z
            │                                  │                             │
            ▼                                  ▼                             ▼
 ┌──────────────────────┐        ┌──────────────────────────┐   ┌─────────────────────────┐
 │ ci.yml               │        │ cd.yml                   │   │ release.yml             │
 │  back : Gradle build │        │  build des 2 images      │   │  build + tests          │
 │         + tests      │        │  scan Trivy              │   │  GitHub Release         │
 │         + JaCoCo     │        │  push GHCR               │   │   (JAR + dist Angular)  │
 │  front : npm ci      │        │   tags : SHA + latest    │   │  images taguées X.Y.Z   │
 │          + tests     │        └──────────────────────────┘   └─────────────────────────┘
 │          + ng build  │
 │  sonar : SonarQube   │
 │          Cloud       │
 └──────────────────────┘
```

Le détail de chaque étape est donné au §2 ; la conteneurisation et le déploiement au §3.

## 2. Étapes de mise en œuvre du pipeline CI/CD

<!-- §2 décrit l'intégration continue (étape 3) et la livraison continue (étape 5). À compléter avec release.yml (étape 6). -->

### 2.1 Structure du pipeline

L'intégration continue est définie dans `.github/workflows/ci.yml`. Elle comporte trois jobs :

```text
            ┌──────────────────────────┐
            │ back  (Gradle, Java 17)  │──┐
push / PR ──┤                          │  ├──► sonar (SonarQube Cloud, quality gate)
nightly     │ front (Node 22, Angular) │──┘
            └──────────────────────────┘
```

| Job | Étapes | Résultat |
|---|---|---|
| `back` | Compilation, tests JUnit, rapport de couverture JaCoCo | Rapport de tests et de couverture (HTML), classes compilées + rapport XML pour SonarQube |
| `front` | `npm ci --ignore-scripts`, `npm audit` (non bloquant), tests Karma en Chrome headless avec couverture, `ng build` | Rapport de couverture (HTML et LCOV), résumé de l'audit npm |
| `sonar` | Récupère les résultats des deux jobs, analyse le code, attend la *quality gate* | Analyse SonarQube Cloud ; le job échoue si la *quality gate* échoue |

**Ordre d'exécution.** `back` et `front` s'exécutent **en parallèle**, puisqu'ils sont indépendants : le retour est plus rapide (environ 1 minute chacun). `sonar` démarre **après les deux** (`needs: [back, front]`), car il a besoin de leurs classes compilées et de leurs rapports de couverture, transmis sous forme d'artefacts. Si un test échoue, `sonar` ne s'exécute pas et le pipeline est rouge.

Chaque job écrit un **résumé** sur la page du run GitHub Actions : nombre de tests réussis ou échoués, couverture, vulnérabilités npm par sévérité. Les rapports HTML sont téléchargeables en artefacts pendant 14 jours. Les résultats sont ainsi lisibles sans ouvrir les logs.

**Protection de `main`.** Une règle (*ruleset*) interdit le push direct sur `main` : toute modification passe par une pull request. La fusion n'est possible que si les trois jobs sont verts. La *quality gate* est donc réellement bloquante (exemple au §5.1).

**Livraison continue (`cd.yml`).** Après chaque push sur `main`, le workflow CD s'exécute, et **uniquement si la CI a réussi** (déclencheur `workflow_run`). Il travaille sur le commit exact validé par la CI :

```text
CI verte sur main ──► build des 2 images ──► test de fumée ──► scan Trivy ──► publication GHCR
                       (docker compose)      (up --wait,       (rapport SARIF   (sha-<commit>
                                              curl API/front)   + porte CRITICAL)  + latest)
```

| Étape | Détail | En cas d'échec |
|---|---|---|
| Build | `docker compose build`, mêmes Dockerfiles qu'en local, images taguées `sha-<commit>` | Arrêt, rien n'est publié |
| Test de fumée | `docker compose up -d --wait` attend que les healthchecks soient verts, puis `curl` sur `/persons` et sur le front | Logs des conteneurs affichés, rien n'est publié |
| Rapport Trivy | Toutes les sévérités, envoyées dans l'onglet *Security* de GitHub (format SARIF) | — (rapport seulement) |
| Porte Trivy | Échec si une vulnérabilité CRITIQUE avec correctif existe dans une image | Rien n'est publié |
| Publication | `docker login` avec le `GITHUB_TOKEN` du job, `docker push` des tags `sha-<commit>` et `latest` | — |

La publication utilise directement la CLI `docker` plutôt que des actions tierces (`docker/login-action`, `docker/build-push-action`). C'est une dépendance de moins à faire confiance, et ce sont les mêmes commandes qu'en local. Le run nightly et les pull requests ne publient jamais d'image.

**Choix des actions GitHub.** Uniquement des actions maintenues et documentées :

| Action | Rôle | Pourquoi |
|---|---|---|
| `actions/checkout`, `actions/setup-java`, `actions/setup-node` | Récupérer le code, installer Java 17 (Temurin) et Node 22 | Actions officielles GitHub ; cache Gradle et npm intégré |
| `actions/upload-artifact`, `actions/download-artifact` | Transmettre les rapports entre jobs, publier les rapports HTML | Actions officielles GitHub |
| `SonarSource/sonarqube-scan-action` | Lancer l'analyse SonarQube Cloud | Action officielle de l'éditeur ; épinglée par SHA de commit (§5) |
| `aquasecurity/trivy-action` | Scanner les images Docker | Action officielle de l'éditeur de Trivy ; épinglée par SHA sur une *release* immuable (voir ci-dessous) |
| `github/codeql-action/upload-sarif` | Envoyer les rapports Trivy dans l'onglet *Security* | Action officielle de GitHub ; épinglée par SHA |

**Pourquoi épingler par SHA : un cas réel.** En mars 2026, les tags de `aquasecurity/trivy-action` ont été détournés : 76 tags sur 77 pointaient vers un code qui volait les secrets des pipelines (avis de sécurité publié par Aqua Security). Les workflows qui référençaient l'action par un tag comme `@v0.34` ont exécuté ce code. Ceux qui l'épinglaient par SHA de commit n'étaient pas touchés. Ce projet épingle donc `trivy-action` sur le SHA de la version 0.36.0, publiée comme *release* immuable après l'incident, et fixe explicitement la version de Trivy utilisée (`v0.70.0`).

Les commandes de build et de test restent celles du projet (`./gradlew`, `npm`), appelées directement plutôt que via des actions tierces : la CI exécute exactement ce qu'un développeur lance en local.

### 2.2 Scripts d'automatisation

| Commande | Objectif | Où elle est définie | Quand elle s'exécute |
|---|---|---|---|
| `./gradlew build jacocoTestReport` | Compiler le back-end, lancer les tests, produire la couverture | `back/build.gradle` (plugins `java`, `jacoco`, Spring Boot) | CI (job `back`), local |
| `./gradlew dependencies --write-locks` | Mettre à jour `gradle.lockfile` après un changement de dépendance | `back/build.gradle` (`dependencyLocking`) | Local, lors d'une mise à jour |
| `npm ci --ignore-scripts` | Installer exactement les versions de `package-lock.json`, sans exécuter les scripts d'installation | `front/package-lock.json` | CI (job `front`), local |
| `npm audit` | Lister les dépendances vulnérables | npm | CI (job `front`, non bloquant) |
| `npm test -- --watch=false --browsers=ChromeHeadlessNoSandbox --code-coverage` | Lancer les tests unitaires du front avec couverture | `front/package.json`, `front/karma.conf.js` | CI (job `front`), local |
| `npm run build` | Construire l'application Angular | `front/package.json`, `front/angular.json` | CI (job `front`), local |
| Analyse SonarQube | Analyser le code et vérifier la *quality gate* | `sonar-project.properties`, job `sonar` | CI (job `sonar`) |

**Adapter le pipeline :**
- ajouter une étape : un `step` dans le job concerné de `ci.yml` ;
- changer le périmètre d'analyse : `sonar-project.properties` ;
- changer les déclencheurs : la section `on:` de `ci.yml` ;
- changer les seuils de qualité : la *quality gate* dans SonarQube Cloud.

**Mises à jour automatiques.** `.github/dependabot.yml` configure Dependabot. Chaque semaine, il propose des pull requests de mise à jour pour npm, Gradle, les images Docker et les actions GitHub. Elles passent par la même CI que tout autre changement.

### 2.3 Reproductibilité

**Relancer le pipeline :**
- automatiquement, à chaque push et pull request, et chaque nuit à 03:00 UTC ;
- manuellement, depuis l'onglet *Actions* → *CI* → *Run workflow* (déclencheur `workflow_dispatch`) ;
- pour un run précis, avec *Re-run jobs* (tous les jobs ou seulement ceux en échec).

**Reproduire en local.** Les commandes du §2.2 sont celles de la CI, avec les mêmes versions : Java 17, Node 22, dépendances figées par `package-lock.json` et `gradle.lockfile`.

**Gestion des secrets :**
- **Un seul secret** : `SONAR_TOKEN`, stocké dans les *GitHub Secrets* du dépôt et dans les *Dependabot secrets* (les pull requests de Dependabot ne reçoivent pas les secrets ordinaires).
- Il est injecté **uniquement** dans le job `sonar`, et GitHub masque sa valeur dans les logs.
- Le jeton n'apparaît dans aucun fichier du dépôt. Pour le renouveler : en générer un nouveau dans SonarQube Cloud, puis exécuter `gh secret set SONAR_TOKEN` (qui demande la valeur sans l'afficher), ou passer par *Settings → Secrets and variables → Actions*.
- Les pull requests venant d'un fork ne reçoivent aucun secret ; le job `sonar` est alors ignoré (§5.2).

## 3. Plan de conteneurisation et de déploiement

Ce plan décrit comment l'application est empaquetée en images Docker, lancée avec Docker Compose et livrée. Il part de l'existant et le fait évoluer sans changer ce qui fonctionne, notamment le serveur web Caddy.

### 3.1 Dockerfiles

**Existant.** Le projet contient un Dockerfile unique à la racine, avec cinq cibles :

| Cible | Rôle |
|---|---|
| `front-build` | Compile l'application Angular avec Node |
| `back-build` | Compile le JAR Spring Boot avec Gradle (JDK 17) |
| `front` | Sert le front avec Caddy, installé par `apk` sur Alpine |
| `back` | Exécute le JAR sur un JRE OpenJDK 21 |
| `standalone` | Front et back dans **un seul conteneur**, lancés par `supervisord` |

L'analyse initiale (§1) a relevé plusieurs défauts :
- `FROM node` sans version ;
- `alpine:3.19` en fin de vie ;
- `EXPOSE 4200` sur l'API, qui écoute sur 8080 ;
- compilation en Java 17 mais exécution en Java 21 ;
- conteneurs exécutés en `root`.

**Choix retenu : un Dockerfile par composant.** Le Dockerfile racine est remplacé par `back/Dockerfile` et `front/Dockerfile`, chacun avec son propre `.dockerignore`.

- **Lisibilité** : chaque fichier ne décrit qu'un composant ; `docker-compose.yml` pointe simplement vers `./back` et `./front`.
- **Sécurité** : le contexte de build se limite au dossier du composant. Le build du back ne reçoit jamais les fichiers du front, et inversement.
- **Évolutivité** : la partie 2 du projet ajoute des services (Elasticsearch, Kibana…) au même `docker-compose.yml` sans restructuration.

Ce remplacement change la façon de déployer : on passe d'un conteneur `standalone` à **deux conteneurs**. Il est traité comme une **migration** : documenté ici, réalisé en une seule modification, avec retour arrière possible vers une version précédente (§7.3).

**Multi-stage build.** Chaque Dockerfile a deux étapes :
1. une étape de **build** qui contient les outils de compilation (JDK, Node, dépendances) ;
2. une étape d'**exécution** qui ne reçoit que le résultat : le JAR pour le back, les fichiers statiques pour le front.

Les outils de build, le code source et les caches ne sont pas dans l'image finale. Elle est plus petite et expose moins de composants vulnérables.

| | Back-end (`back/Dockerfile`) | Front-end (`front/Dockerfile`) |
|---|---|---|
| Étape build | `eclipse-temurin:17-jdk-alpine` + wrapper Gradle → `bootJar` | `node:22-alpine` → `npm ci --ignore-scripts` + `ng build` |
| Étape exécution | `eclipse-temurin:17-jre-alpine` | image officielle `caddy` (Alpine) |
| Port interne | 8080 | 8080 |
| Utilisateur | non privilégié | non privilégié |

**Justification des images.**
- **Back-end** : `eclipse-temurin:17-jre-alpine` est l'image officielle de la distribution Java Temurin. Elle reprend la version de compilation (17), ce qui supprime l'écart avec Java 21, et reste légère. Une image *distroless* réduirait encore la surface d'attaque, mais sans shell le diagnostic devient difficile : c'est une évolution à long terme (§5.3).
- **Node 22 LTS** : seule l'étape de build utilise Node ; l'image finale n'en contient pas (voir §1 pour l'écart avec les versions supportées par Angular 17).
- **Front-end, Caddy conservé** : Caddy est le serveur déjà utilisé. En production, son atout est le **HTTPS automatique** (certificat Let's Encrypt obtenu et renouvelé seul pour le nom de domaine). Passer à nginx obligerait à gérer les certificats soi-même et à migrer une configuration en production. Ce serait aussi changer deux choses à la fois pendant l'arrivée de la CI/CD, pour un gain faible. Caddy est donc conservé, mais modernisé :
  - **Image officielle** `caddy`, au lieu de `apk add caddy` sur une Alpine en fin de vie.
  - **Utilisateur non privilégié**, qui écoute sur le port 8080 dans le conteneur.
  - **Adresse du site passée par la variable `SITE_ADDRESS`** :
    - en local, HTTP simple sur `:8080`, donc plus de certificat auto-signé ni d'avertissement du navigateur ;
    - en production, le nom de domaine, et Caddy active le HTTPS automatiquement.

    La même image sert dans les deux cas.

**Optimisations simples.**
- Versions d'images figées.
- `.dockerignore` excluant `node_modules`, `build`, `dist` et les caches.
- Dépendances copiées et installées avant le code source, pour profiter du cache Docker.
- Compression gzip côté Caddy.
- Aucun secret dans les images.

**Vérification après mise en place**

| Contrôle | Ancien Dockerfile racine | Nouveaux Dockerfiles |
|---|---|---|
| Utilisateur dans le conteneur | `root` | `app` (back), `web` (front) |
| Version Java à l'exécution | 21 (compilé en 17) | 17 |
| Taille de l'image back | 373 Mo | 356 Mo |
| Taille de l'image front | 78 Mo | 92 Mo |
| Front servi en | HTTPS auto-signé (avertissement navigateur) | HTTP local, HTTPS automatique en production |

L'image du front est un peu plus lourde : l'image officielle `caddy` remplace un paquet `apk`. Ce léger surcoût est accepté en échange d'une image maintenue par l'éditeur et figée en version.

### 3.2 docker-compose.yml

`docker-compose.yml` décrit l'application complète :

| Service | Build | Image publiée | Port hôte → conteneur | Variables |
|---|---|---|---|---|
| `back` | `./back` | `ghcr.io/m0l42/microcrm-back` | `8080 → 8080` | `APP_CORS_ORIGINS=http://localhost:4200` |
| `front` | `./front` | `ghcr.io/m0l42/microcrm-front` | `4200 → 8080` | `SITE_ADDRESS=:8080` |

Il n'y a pas de service de base de données : l'API utilise HSQLDB **en mémoire**, intégrée au processus Java. Les données sont perdues à chaque redémarrage (voir §7).

Le port 8080 de l'API est publié sur l'hôte, car le front appelle l'API **depuis le navigateur**, à l'adresse `http://localhost:8080` définie dans `front/src/app/config.ts`. L'origine autorisée par CORS est donc celle du front, `http://localhost:4200`.

Chaque service a un **healthcheck** : Docker interroge le service toutes les 10 secondes et le marque `healthy` ou `unhealthy` (`make ps`). Chaque service déclare à la fois `build:` et `image:`. Le même fichier sert ainsi à **construire** l'application en local et à **déployer** une version publiée (§3.3).

**Lancer l'application en local**

```bash
make up          # équivaut à : docker compose up -d --build
make logs        # suivre les logs des deux services
make down        # arrêter et supprimer les conteneurs
```

L'application est alors accessible sur http://localhost:4200, et l'API sur http://localhost:8080.

Le `Makefile` regroupe les commandes courantes (`build`, `test`, `up`, `down`, `logs`). La CI appelle directement `./gradlew` et `npm` plutôt que `make`, pour que chaque étape reste visible dans les logs GitHub Actions.

### 3.3 Stratégie de déploiement

Orion n'ayant pas d'environnement de production accessible dans le cadre de ce projet, le « déploiement » couvre deux choses :
- la **publication des images** sur GitHub Container Registry (GHCR) ;
- une **procédure de mise en production** reproductible avec Docker Compose.

**Publication automatique des images**

| Déclencheur | Workflow | Tags publiés | Usage |
|---|---|---|---|
| Push sur `main` (après fusion), une fois la CI verte | `cd.yml` | `sha-<commit>` et `latest` | Dernière version validée ; le tag par commit permet de retrouver exactement le code d'une image |
| Tag Git `vX.Y.Z` | `release.yml` | `X.Y.Z` | Version livrée, immuable, utilisée en production |

Avant toute publication, les images passent par le scan Trivy et le test de fumée (§4, §5) ; un échec bloque la publication. L'authentification à GHCR utilise le `GITHUB_TOKEN` du job : aucun secret supplémentaire n'est nécessaire.

**Release.** Une version est décidée par un humain, qui pousse le tag `vX.Y.Z` : c'est l'étape de validation volontaire avant livraison. Le workflow crée alors une *GitHub Release* contenant le JAR du back-end et une archive du build Angular, et publie les images taguées `X.Y.Z`.

**Mise en production (procédure).** Sur le serveur, le même `docker-compose.yml` récupère les images publiées au lieu de les construire :

```bash
TAG=1.0.0 docker compose pull
TAG=1.0.0 docker compose up -d
```

Le retour arrière consiste à relancer ces commandes avec la version précédente (`TAG=0.9.0`).

**Évolution prévue.** Une fois un serveur disponible, un job `deploy` ajouté à `release.yml` exécutera cette procédure par SSH, avec la clé et l'adresse du serveur stockées en *GitHub Secrets*. Le déploiement sera alors entièrement automatisé.

**Visibilité du dépôt.** Le dépôt et les images sont publics pour les besoins du projet de formation. Dans un contexte réel, ils seraient **privés**. Le serveur devrait alors s'authentifier avant le `pull` (`docker login ghcr.io` avec un jeton en lecture seule, `read:packages`). L'offre SonarQube Cloud et l'onglet *Security* de GitHub (*code scanning*) seraient alors payants pour un dépôt privé.

## 4. Plan de testing périodique

Ce plan définit quels tests sont exécutés automatiquement, à quel moment et dans quel but. Il s'appuie sur les tests existants du projet : en écrire de nouveaux ne fait pas partie de la mission. Il y ajoute un seul contrôle : un test de fumée (*smoke test*) sur les images Docker avant leur publication.

### 4.1 Types de tests automatisés

| Type | Composant | Contenu | Outil | Étape |
|---|---|---|---|---|
| Test d'intégration | Back-end | `contextLoads` : l'application Spring Boot démarre et sa configuration est valide | JUnit 5, Gradle | CI |
| Test d'intégration | Back-end | `PersonRepositoryIntegrationTest` : recherche d'une personne par e-mail sur une vraie base (HSQLDB) | JUnit 5, Spring Data | CI |
| Test d'intégration | Back-end | `CorsConfigurationTest` (2 tests, ajoutés avec la correction CORS) : une requête de l'origine autorisée est acceptée, une autre origine est refusée (403) | JUnit 5, MockMvc | CI |
| Tests unitaires | Front-end | 8 tests répartis dans 6 fichiers : 2 services (`PersonService`, `OrganizationService`) et 4 composants | Karma, Jasmine, Chrome headless | CI |
| Couverture de code | Back + front | Part du code exécutée par les tests | JaCoCo (back), Istanbul/LCOV (front) | CI |
| Analyse statique | Back + front | Bugs, vulnérabilités, *code smells*, duplication (détail au §5) | SonarQube Cloud | CI |
| Test de fumée | Images Docker | Les conteneurs fraîchement construits démarrent ; l'API (`/persons`) et la page d'accueil du front répondent `200` | Docker Compose, `curl` | CD |

Le test de fumée ne remplace pas les tests fonctionnels. Il vérifie ce qu'aucun test unitaire ne voit : que l'image construite démarre réellement, avec la bonne configuration et sur le bon port. Le Dockerfile existant exposait par exemple le port 4200 pour l'API, qui écoute sur 8080 : une erreur de ce type est détectée avant la publication.

### 4.2 Fréquence d'exécution

| Déclencheur | Ce qui s'exécute | Pourquoi |
|---|---|---|
| **Push** sur n'importe quelle branche | CI : build, tests back et front, couverture, analyse SonarQube | Retour rapide au développeur, avant même d'ouvrir une pull request |
| **Pull request** vers `main` | CI complète + *quality gate* SonarQube affichée sur la PR | Rien de cassé ni de non conforme n'est fusionné dans `main` |
| **Nightly** : tous les jours à 03:00 UTC, sur `main` | CI complète | Détecter ce qui change sans modification du code : nouvelle vulnérabilité publiée, dépendance ou image de base devenue incompatible |
| **Push sur `main`** (après fusion) | CD : construction des images, scan Trivy, test de fumée, puis publication sur GHCR | Ne publier que des images qui démarrent et ne contiennent pas de faille critique corrigeable |
| **Tag `vX.Y.Z`** (avant release) | Build et tests complets, puis création de la release | Une version livrée est toujours une version retestée |

### 4.3 Critères de réussite et d'alerte

Le pipeline **échoue**, et bloque la fusion ou la publication, dans les cas suivants :

- un seul test back-end ou front-end échoue ;
- la *quality gate* SonarQube échoue (détail au §5) ;
- le test de fumée n'obtient pas une réponse `200` de l'API ou du front.

La *quality gate* utilisée est celle par défaut de SonarQube Cloud (« Sonar way »). Elle ne juge que le **nouveau code** : au moins 80 % de couverture sur les lignes ajoutées, aucun nouveau bug, aucune nouvelle vulnérabilité, et tous les *security hotspots* revus. Ce choix est réaliste au vu de l'état initial (environ 31 % de couverture côté front). Un seuil global ferait échouer la CI dès le premier jour sans rien améliorer. Avec cette règle, chaque modification doit être testée et la couverture progresse avec le code.

La **couverture globale** est suivie dans SonarQube comme indicateur, sans bloquer. Aucun seuil n'est imposé dans Gradle ou Karma, pour ne garder qu'une seule source de vérité.

**Alertes** : un échec est visible dans l'onglet Actions et sur la pull request. GitHub envoie un e-mail en cas d'échec d'un workflow, y compris pour le run nightly.

### 4.4 Objectifs des tests

- **Qualité** : l'analyse SonarQube et la *quality gate* empêchent l'ajout de code non testé ou présentant des défauts connus.
- **Non-régression** : les tests existants sont rejoués à chaque push, sur chaque pull request et chaque nuit. Une modification qui casse un comportement existant est détectée avant d'atteindre `main`.
- **Vérification avant déploiement** : le test de fumée garantit que les images publiées sur GHCR démarrent et répondent. Une version taguée est entièrement retestée avant la release.
- **Limites assumées** : 12 tests (dont 2 ajoutés avec la correction CORS) couvrent une petite partie de l'application. L'ajout de tests (contrôleurs REST, scénarios end-to-end) est une recommandation pour les itérations suivantes (§9). Il ne relève pas de la mise en place du pipeline.

## 5. Plan de sécurité

Ce plan fixe les contrôles de sécurité intégrés au pipeline et la façon de traiter les risques identifiés. Il suit un principe simple : **identifier, évaluer, recommander, remonter**. Corriger directement ce qui est peu coûteux et relève du déploiement ; soumettre le reste à la direction technique, propriétaire du risque, avec un plan priorisé. Aucun risque n'est « accepté » sans décision explicite de sa part.

### Rôle de SonarQube Cloud

SonarQube Cloud analyse le code back-end (Java) et front-end (TypeScript) à chaque exécution de la CI. Le dépôt étant public, l'offre gratuite suffit. L'analyse surveille :

| Type de problème | Exemple |
|---|---|
| **Vulnérabilités** | Faille exploitable dans le code |
| **Security hotspots** | Code sensible à revoir manuellement, par exemple une configuration CORS ouverte à toutes les origines |
| **Bugs** | Erreur de logique probable |
| **Code smells** | Code difficile à maintenir : complexité, duplication, mauvaises pratiques |
| **Couverture** | Rapports JaCoCo (back) et LCOV (front) importés à chaque analyse |

La *quality gate* (§4.3) bloque une pull request qui introduit un bug, une vulnérabilité, un *hotspot* non revu ou du code non testé.

### Contrôles complémentaires dans le pipeline

- **Dépendances** : `npm audit` s'exécute dans la CI et affiche son rapport sans bloquer. L'état initial (90 vulnérabilités, dont 5 critiques) ferait échouer chaque exécution jusqu'à la montée de version d'Angular et masquerait les autres signaux. **Dependabot** surveille npm, Gradle, les images Docker et les actions GitHub : il ouvre des pull requests de mise à jour et des alertes de sécurité.
- **Images Docker** : **Trivy** scanne chaque image avant sa publication, paquets système et bibliothèques Java du JAR compris. La publication est **bloquée** si une vulnérabilité CRITIQUE disposant d'un correctif est trouvée. Toutes les sévérités sont envoyées dans l'onglet *Security* de GitHub (format SARIF).
- **Images de base** : uniquement des images officielles, en version figée (`eclipse-temurin:17-jre-alpine`, `caddy`, `node:22-alpine`). Les conteneurs s'exécutent avec un utilisateur non privilégié.
- **Secrets** :
  - un seul secret stocké, `SONAR_TOKEN`, dans les *GitHub Secrets* ;
  - la publication sur GHCR utilise le `GITHUB_TOKEN` fourni automatiquement à chaque job, qui expire avec lui ;
  - aucun secret dans le code, les images, les artefacts ou les logs ;
  - *secret scanning* et *push protection* sont activés sur le dépôt : un push contenant un jeton est refusé.
- **Permissions minimales** : chaque workflow démarre en `contents: read` et n'ajoute que ce dont un job a besoin (`packages: write` pour publier les images, `contents: write` pour créer une release, `security-events: write` pour les rapports Trivy).
- **Actions GitHub** : uniquement des actions maintenues et documentées, tenues à jour par Dependabot. Les actions officielles de GitHub (`actions/*`) sont référencées par version majeure (`actions/checkout@v7`). Les actions **tierces** (SonarQube, Trivy, Docker) sont **épinglées par SHA de commit**, car un tag peut être déplacé par son propriétaire, pas un SHA. Ce choix a été révisé après la première analyse SonarQube, qui a signalé l'épinglage par tag comme une vulnérabilité (règle `githubactions:S7637`).

### 5.1 Résultats SonarQube

**Première analyse complète de `main`** (22/11/2026, 1 412 lignes analysées), puis état après les corrections réalisées dans ce projet :

| Mesure | Analyse initiale | Après corrections |
|---|---|---|
| Couverture globale | 28,4 % (lignes 30 %, branches 13,8 %) | **38,0 %** (lignes 41,7 %, branches 13,8 %) |
| Vulnérabilités | 6 (note de sécurité C) | **4**, toutes dans l'ancien Dockerfile racine |
| Bugs | 20 (note de fiabilité C) | 20 |
| Code smells | 9 (note de maintenabilité A, ~40 min de dette) | 9 |
| Security hotspots | 0 | 0 |
| Duplication | 1,6 % | 1,6 % |
| Tests back-end | 2 | 4 |

**Vulnérabilités identifiées**

| Règle | Fichier | Problème | Traitement |
|---|---|---|---|
| `docker:S6505`, `docker:S8543` (×3) | `Dockerfile` (racine) | `npm ci` sans `--ignore-scripts`, `npx` sans version fixée | Fichier remplacé à l'étape 4 (§3.1) |
| `docker:S6471` | `Dockerfile` (racine) | Image Alpine exécutée en `root` | Utilisateur non privilégié (§3.1) |
| `text:S8569` | `back/build.gradle` | Versions de dépendances non verrouillées | **Corrigé** : `gradle.lockfile` |
| `Web:S5725` | `front/src/index.html` | Feuille de style Bulma chargée depuis un CDN sans contrôle d'intégrité | **Corrigé** : empreinte SRI `sha384` |

**Code smells et bugs principaux.** Ils concernent le code applicatif du front, hors du périmètre du pipeline. Ils sont transmis à l'équipe de développement (§5.3) :
- 12 promesses dont les erreurs ne sont jamais traitées (`fetchAll().then(...)` sans `.catch`). Une erreur de l'API passe inaperçue pour l'utilisateur.
- 7 champs de formulaire sans libellé associé et un tableau sans en-têtes : problèmes d'accessibilité.
- 1 smell **critique** (`typescript:S7059`) : un appel asynchrone dans le constructeur de `PersonDetailsComponent`.

**Zones de complexité.** La complexité reste faible (114 en cyclomatique, 18 en cognitive pour tout le projet). Les composants les plus lourds sont `person-details` (78 lignes TypeScript, 203 lignes de template) et `organization-details`. Ce sont aussi les moins couverts (27 % et 36 %).

**Couverture des tests.** La première mesure était faussée : les fichiers de test eux-mêmes étaient comptés comme du code à couvrir, à 0 %. Après les avoir exclus de la mesure et ajouté des tests CORS, la couverture passe de 28,4 % à 38 %. Elle reste faible, notamment sur les services front (12 à 15 %). La *quality gate* impose désormais 80 % sur tout nouveau code.

**Ce que la mise en place a montré**
- **Le pipeline s'est contrôlé lui-même.** La première analyse a signalé 6 vulnérabilités dans le workflow `ci.yml` : scripts npm exécutés à l'installation, `npx` sans version, action tierce référencée par tag. Elles ont été corrigées avant la première fusion. Le choix d'épingler les actions tierces par SHA a été révisé suite à cette analyse.
- **La *quality gate* est réellement bloquante.** La pull request de correction CORS a d'abord été bloquée à 25 % de couverture du nouveau code : son nouveau fichier de test était encore compté comme du code à couvrir. Après fusion de la correction de mesure, la couverture du nouveau code est de 100 % et la fusion a été autorisée.
- **L'analyse automatique ne remplace pas la revue manuelle.** SonarQube n'a pas signalé la configuration CORS ouverte à toutes les origines (0 *security hotspot*). Elle a été détectée par revue de code et corrigée (§5.2).

<!-- Annexes : captures du tableau de bord SonarQube (avant/après), de la PR bloquée par la quality gate, d'un résumé de run. -->

### 5.2 Analyse des risques

L'application manipule des **données personnelles** (noms, e-mails, organisations) : le RGPD s'applique. La sévérité tient compte du contexte, une application interne aujourd'hui accessible uniquement sur le réseau de l'entreprise.

**Risques applicatifs (OWASP Top 10, 2021)**

| Réf. | Risque constaté | Impact | Sévérité | Traitement |
|---|---|---|---|---|
| A01 – Broken Access Control | L'API n'a **aucune authentification** : quiconque atteint le port 8080 peut lire, créer, modifier et supprimer toutes les données | Fuite ou destruction de données personnelles | **Élevée** | Remonté à la direction technique, priorité n°1 |
| A05 – Security Misconfiguration | CORS autorise **toutes les origines** (`allowedOrigins("*")` et `@CrossOrigin` sur les deux dépôts REST) | N'importe quel site web peut appeler l'API depuis le navigateur d'un utilisateur | Moyenne | Corrigé dans ce projet |
| A06 – Vulnerable and Outdated Components | 90 vulnérabilités npm (5 critiques). Angular 17 et Spring Boot 3.2 ne sont plus maintenus | Failles connues et publiques, sans correctif côté éditeur | **Élevée** | Plan de mise à jour (§8) |
| A02 – Cryptographic Failures | L'API est servie en HTTP : les données circulent en clair | Interception sur le réseau | Moyenne | HTTPS via Caddy en production |
| A09 – Security Logging and Monitoring Failures | Pas de journalisation centralisée ni d'alerte | Une attaque passerait inaperçue | Moyenne | Partie 2 (stack ELK) |

**Risques liés au pipeline**

| Risque | Mesure en place |
|---|---|
| Secret exposé dans le code ou les logs | Secrets GitHub masqués dans les logs, *secret scanning* + *push protection*, un seul secret stocké |
| Jeton aux droits trop larges | `GITHUB_TOKEN` éphémère, permissions minimales par workflow |
| Action GitHub compromise (chaîne d'approvisionnement) | Actions officielles ou d'éditeurs reconnus, actions tierces épinglées par SHA, mises à jour suivies par Dependabot |
| Image publiée avec une faille critique ou qui ne démarre pas | Scan Trivy bloquant et test de fumée avant publication, publication seulement après une CI verte |
| Dépendance devenue vulnérable sans modification du code | Exécution nightly, alertes Dependabot |
| Image de base non maintenue ou non figée | Images officielles en version figée, mises à jour proposées par Dependabot |
| Conteneur compromis avec les droits `root` | Utilisateur non privilégié dans les deux images |
| Pull request venant d'un fork | GitHub ne transmet pas les secrets aux workflows déclenchés par un fork : l'analyse SonarQube n'y tourne pas, la PR est revue manuellement avant fusion |

### 5.3 Plan d'action / Remédiation

**Actions immédiates (réalisées dans ce projet)**

- ✅ Restreindre CORS à l'origine du front, configurée par la variable d'environnement `APP_CORS_ORIGINS`, et supprimer les annotations `@CrossOrigin`. Tests ajoutés : origine autorisée acceptée, autre origine refusée (403).
- ✅ Verrouiller les dépendances Gradle (`gradle.lockfile`) et contrôler l'intégrité de la feuille de style chargée depuis un CDN (SRI).
- Conteneurs non `root`, images de base officielles et figées, scan Trivy bloquant.
- *Quality gate* SonarQube sur chaque pull request ; revue des *security hotspots*.
- Dependabot, *secret scanning*, *push protection*, permissions minimales dans les workflows.
- Remonter l'absence d'authentification à la direction technique, avec une condition : **l'application ne doit pas être exposée hors du réseau interne tant que ce point n'est pas traité.**

**Court terme (prochaines itérations)**

- Décision de la direction technique sur l'authentification : comptes internes ou SSO de l'entreprise, rôles nécessaires.
- Traiter les 5 vulnérabilités npm critiques : `npm audit fix` pour celles qui le permettent, puis montée de version d'Angular vers une version maintenue.
- Passer Spring Boot sur une version maintenue (branche 3.x supportée).
- Transmettre à l'équipe de développement les 20 bugs relevés par SonarQube dans le front : gestion des erreurs des promesses, accessibilité des formulaires.

**Long terme**

- Mettre en place l'authentification (Spring Security + OpenID Connect) côté API et front.
- Servir l'API derrière Caddy en HTTPS, sans exposer directement le port 8080.
- Étendre l'épinglage par SHA aux actions officielles `actions/*`.
- Évaluer une image d'exécution *distroless* pour réduire encore la surface d'attaque.
- Remplacer HSQLDB en mémoire par une base persistante sauvegardée (§7).

## 6. Monitoring, métriques & KPI

<!-- À compléter en partie 2 (stack ELK). -->

### 6.1 Métriques DORA

> TODO (partie 2) : Lead Time, Deployment Frequency, MTTR, Change Failure Rate (méthode de calcul + valeurs observées).

### 6.2 KPI personnalisés

> TODO (partie 2) : temps de build, temps des tests, taux d'erreurs dans les logs, autre KPI pertinent.

### 6.3 Analyse synthétique du monitoring

> TODO (partie 2) : tendances observées, points forts, points à améliorer, dashboards, alertes.

## 7. Plan de sauvegarde des données

### 7.1 Ce qui doit être sauvegardé

> TODO :
> - Données (si applicable : la base HSQLDB actuelle est en mémoire)
> - Fichiers de configuration
> - Artefacts de build

### 7.2 Procédure de sauvegarde

> TODO : format, fréquence, outils utilisés (scripts, commandes simples).

### 7.3 Procédure de restauration

> TODO : scénario d'incident, étapes pour revenir à une version stable, limitations éventuelles.

## 8. Plan de mise à jour

### 8.1 Mise à jour de l'application

> TODO : dépendances Gradle / npm, mises à jour Angular / Spring Boot, mises à jour des images Docker.

### 8.2 Mise à jour du pipeline CI/CD

> TODO : versions des actions GitHub, versions des scripts, maintenance du workflow.

### 8.3 Fréquence & bonnes pratiques

> TODO : conseils pour maintenir la solution dans le temps.

## 9. Conclusion

> TODO :
> - Résumé des améliorations apportées
> - Gains observés (fiabilité, rapidité, qualité)
> - Recommandations pour les itérations suivantes

## Annexes

> TODO (optionnel) : captures SonarQube, captures de logs, extraits de workflows, commandes utiles.
