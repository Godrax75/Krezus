# Le catalogue de titres

Un peu plus de **1 190 lignes**, dont environ 1 160 actions et 30 ETF, sur
douze places et huit devises. Tout est ramené à l'euro à l'affichage ; les
cours natifs et le taux appliqué restent en base, pour qu'un chiffre puisse
toujours être remonté à sa source.

| Origine | Titres | Place |
|---|---|---|
| Sélection d'origine, rédigée à la main | 80 | Paris, Amsterdam, New York |
| S&P 500 | 487 | New York, Nasdaq |
| SBF 120 | 78 | Paris, Amsterdam, Bruxelles |
| FTSE 100, DAX, SMI, AEX, IBEX 35, OMX Stockholm 30 / Copenhague 25 / Helsinki 25, BEL 20 | ~290 | Europe |
| S&P/TSX 60 | 60 | Toronto |
| Hang Seng | 84 | Hong Kong |
| Valeurs connues cotées à New York hors S&P 500 | ~95 | Toyota, Sony, TSMC, Spotify, MercadoLibre… |

**Milan manque** : la Borsa Italiana n'est pas dans l'abonnement EODHD, et un
titre dont on ne peut pas lire le cours n'a rien à faire au catalogue. Le
Japon passe par les lignes cotées à New York, faute de place de Tokyo dans
l'abonnement.

## Les quatre outils

Tous produisent un fichier SQL dans `supabase/seed/`, rejouable : ce qui a
été rédigé à la main n'est jamais écrasé.

```bash
python3 tools/build_index_seed.py sp500|sbf120|global   # composition
python3 tools/build_fiches.py                           # « Que fait l'entreprise ? »
python3 tools/build_dividends.py                        # rendement du dividende
tools/check_index_logos.sh                              # logos disponibles chez EODHD
```

### Composition — `build_index_seed.py`

Wikipédia donne la composition des indices, Wikidata l'ISIN et le logo,
EODHD le mnémonique et la devise. Une société cotée sur plusieurs places
n'entre qu'une fois : l'ISIN fait foi. Les pièges rencontrés sont documentés
dans le fichier — ISIN périmé après un regroupement d'actions, ISIN de la
maison mère hérité par une filiale détachée, homonymie de mnémoniques entre
Paris et New York.

### Fiches — `build_fiches.py`

L'offre Fundamentals d'EODHD, qui fournirait descriptions et ratios, n'est
pas dans l'abonnement. La description vient donc du premier paragraphe de
l'article Wikipédia, condensé en deux phrases par langue. **Rien n'est
ajouté à ce que l'article dit** : c'est la consigne donnée au modèle, et
c'est ce qui sépare un résumé d'une invention. Comptez quelques centimes
d'API par centaine de fiches.

### Dividende — `build_dividends.py`

Somme des dividendes **réellement versés** sur douze mois, rapportée au
cours. Un titre qui n'a rien versé n'apparaît pas : sa fiche affiche « — »,
ce qui est la vérité, et non un rendement de zéro.

## Ce qui reste absent, et pourquoi

| Donnée | État | Raison |
|---|---|---|
| PER, PEG | « — » | Exige le bénéfice par action : offre Fundamentals |
| Capitalisation | « — » | Exige le nombre d'actions en circulation : même offre |
| Dirigeant, date de création | « — » hors titres d'origine | Récupérable depuis Wikidata, pas encore fait |

Ces champs affichent un tiret cadratin, jamais un zéro : une donnée absente
et une donnée nulle ne se confondent pas.

## Entretien

- **Les cours** se rafraîchissent par rotation (45 titres par minute, places
  ouvertes d'abord) et à la demande quand on ouvre une fiche. Voir
  `docs/quotes.md` si ce budget doit changer.
- **L'historique quotidien** est complété chaque soir en quatre parts.
- **La composition des indices bouge** : quelques entrées et sorties par an.
  Rejouer `build_index_seed.py` puis `build_fiches.py` suffit à rattraper ;
  les titres sortis d'un indice restent au catalogue, ce qui est voulu — on
  ne retire pas de la vue un titre que quelqu'un détient.
- **La base pèse environ 330 Mo** (1,3 million de cours quotidiens, huit
  paires de change depuis 2006). L'offre gratuite de Supabase s'arrête à
  500 Mo : au-delà, il faudra soit passer à l'offre payante, soit raccourcir
  l'historique des titres que personne ne détient.
