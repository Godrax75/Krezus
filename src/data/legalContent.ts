/**
 * Textes légaux de l'application.
 *
 * ⚠️ AVANT PUBLICATION : les champs `COMPANY` marqués « À COMPLÉTER » doivent
 * être renseignés avec les informations réelles de l'éditeur. Les mentions
 * légales et la politique de confidentialité sont obligatoires (App Store
 * guideline 5.1.1, RGPD art. 13), et une URL publique de la politique de
 * confidentialité doit en plus être fournie dans App Store Connect.
 *
 * Ces textes décrivent l'app telle qu'elle fonctionne aujourd'hui :
 * portefeuille simulé et données stockées uniquement sur l'appareil. Ils
 * devront être revus quand le backend arrivera (comptes serveur, sous-traitants).
 */

export const COMPANY = {
  legalName: '[À COMPLÉTER — raison sociale]',
  legalForm: '[À COMPLÉTER — forme juridique et capital social]',
  registration: '[À COMPLÉTER — RCS et numéro SIREN]',
  address: '[À COMPLÉTER — adresse du siège social]',
  publicationDirector: '[À COMPLÉTER — nom du directeur de la publication]',
  host: '[À COMPLÉTER — hébergeur et son adresse]',
  /** Renseigner pour activer « Contacter le support » dans le profil. */
  supportEmail: '[À COMPLÉTER — adresse e-mail de contact]',
};

/** `true` quand la valeur a été remplacée par une vraie donnée. */
export function isConfigured(value: string): boolean {
  return !value.startsWith('[À COMPLÉTER');
}

export interface LegalSection {
  heading: string;
  body: string;
}

export interface LegalDocument {
  title: string;
  updatedAt: string;
  sections: LegalSection[];
}

export type LegalDocumentId = 'cgu' | 'privacy' | 'notices';

const LAST_UPDATE = '15 septembre 2026';

export const LEGAL_DOCUMENTS: Record<LegalDocumentId, LegalDocument> = {
  cgu: {
    title: 'Conditions générales d\'utilisation',
    updatedAt: LAST_UPDATE,
    sections: [
      {
        heading: '1. Objet',
        body: "Les présentes conditions régissent l'utilisation de l'application mobile Krezus, éditée par " +
          COMPANY.legalName +
          ". L'utilisation de l'application vaut acceptation pleine et entière des présentes conditions.",
      },
      {
        heading: '2. Nature du service',
        body: "Krezus est une application pédagogique. Le portefeuille présenté dans l'application est un " +
          "portefeuille SIMULÉ : il permet de suivre l'évolution d'actions réelles à partir de cours de marché, " +
          "mais aucun titre financier n'est détenu, acheté ou vendu pour votre compte, et aucune somme d'argent " +
          "n'est engagée. L'application ne donne accès à aucun service de courtage, de dépôt ou d'exécution d'ordres.",
      },
      {
        heading: '3. Absence de conseil en investissement',
        body: "Les contenus de l'application, y compris les modules pédagogiques, les cours et les actualités, sont " +
          "fournis à titre informatif. Ils ne constituent ni un conseil en investissement, ni une recommandation " +
          "personnalisée, ni une sollicitation d'achat ou de vente d'instruments financiers. Les performances " +
          "passées ne préjugent pas des performances futures.",
      },
      {
        heading: '4. Activation du coffret',
        body: "L'accès à l'application nécessite un code d'activation fourni avec un coffret Krezus. Ce code est " +
          "personnel et ne peut être utilisé qu'une seule fois. Toute tentative de contournement du mécanisme " +
          "d'activation peut entraîner la suspension de l'accès.",
      },
      {
        heading: '5. Compte utilisateur',
        body: "La création d'un compte requiert un prénom, une adresse e-mail et un mot de passe. Vous êtes " +
          "responsable de la confidentialité de vos identifiants et des activités réalisées depuis votre compte. " +
          "Vous pouvez supprimer votre compte à tout moment depuis l'écran Profil ; cette suppression est définitive.",
      },
      {
        heading: '6. Données de marché',
        body: "Les cours affichés proviennent d'un fournisseur de données tiers et sont différés (usuellement " +
          "d'environ quinze minutes). Ils sont fournis à titre indicatif, sans garantie d'exactitude, " +
          "d'exhaustivité ou de disponibilité. En cas d'indisponibilité du fournisseur, l'application affiche des " +
          "données de démonstration, ce qui est signalé à l'écran.",
      },
      {
        heading: '7. Propriété intellectuelle',
        body: "L'application, sa charte graphique, ses contenus pédagogiques et ses composants logiciels sont " +
          "protégés par le droit de la propriété intellectuelle. Toute reproduction ou réutilisation non autorisée " +
          "est interdite. Les marques et logos des sociétés cotées appartiennent à leurs titulaires respectifs.",
      },
      {
        heading: '8. Responsabilité',
        body: "L'éditeur met en œuvre les moyens raisonnables pour assurer le bon fonctionnement de l'application, " +
          "sans garantie de disponibilité continue ni d'absence d'erreur. Sa responsabilité ne saurait être engagée " +
          "à raison de décisions prises sur la base des informations présentées, celles-ci étant de nature " +
          "pédagogique et portant sur un portefeuille simulé.",
      },
      {
        heading: '9. Évolution des conditions',
        body: "Les présentes conditions peuvent être modifiées pour tenir compte d'évolutions légales ou " +
          "fonctionnelles. La version applicable est celle affichée dans l'application à la date d'utilisation.",
      },
      {
        heading: '10. Droit applicable',
        body: "Les présentes conditions sont soumises au droit français. À défaut de résolution amiable, tout " +
          "litige relève de la compétence des tribunaux français.",
      },
    ],
  },

  privacy: {
    title: 'Politique de confidentialité',
    updatedAt: LAST_UPDATE,
    sections: [
      {
        heading: 'Responsable du traitement',
        body: COMPANY.legalName + ', ' + COMPANY.address +
          ". Pour toute question relative à vos données : " + COMPANY.supportEmail + '.',
      },
      {
        heading: 'Données collectées',
        body: "L'application traite : votre prénom et votre adresse e-mail (création du compte), le code " +
          "d'activation de votre coffret, votre progression dans les modules pédagogiques, vos préférences " +
          "d'affichage et de notifications. Aucune donnée bancaire n'est collectée, l'application n'impliquant " +
          "aucun paiement ni aucune somme d'argent.",
      },
      {
        heading: 'Où sont stockées ces données',
        body: "Dans la version actuelle, ces informations sont enregistrées localement sur votre appareil et ne " +
          "sont pas transmises à un serveur de l'éditeur. La désinstallation de l'application ou la suppression " +
          "du compte depuis l'écran Profil efface ces données de l'appareil.",
      },
      {
        heading: 'Finalités et bases légales',
        body: "Les données sont traitées pour fournir le service (exécution du contrat), mémoriser vos " +
          "préférences (intérêt légitime) et vous adresser des notifications si vous les avez activées (consentement).",
      },
      {
        heading: 'Destinataires',
        body: "L'application interroge un fournisseur de données financières tiers pour obtenir les cours et les " +
          "actualités des sociétés suivies. Ces requêtes portent uniquement sur des symboles boursiers : aucune " +
          "donnée personnelle ne lui est transmise.",
      },
      {
        heading: 'Durée de conservation',
        body: "Les données sont conservées tant que le compte existe sur l'appareil, et sont effacées lors de la " +
          "suppression du compte ou de la désinstallation de l'application.",
      },
      {
        heading: 'Vos droits',
        body: "Conformément au RGPD, vous disposez d'un droit d'accès, de rectification, d'effacement, de " +
          "limitation, d'opposition et de portabilité. Le droit d'effacement s'exerce directement depuis l'écran " +
          "Profil (« Supprimer mon compte »). Pour les autres droits, écrivez à " + COMPANY.supportEmail +
          ". Vous pouvez également introduire une réclamation auprès de la CNIL.",
      },
      {
        heading: 'Mineurs',
        body: "L'application s'adresse à un public majeur. Si vous constatez qu'un compte a été créé par un " +
          "mineur sans autorisation parentale, signalez-le à l'adresse de contact afin qu'il soit supprimé.",
      },
    ],
  },

  notices: {
    title: 'Mentions légales',
    updatedAt: LAST_UPDATE,
    sections: [
      {
        heading: 'Éditeur',
        body: COMPANY.legalName + ' — ' + COMPANY.legalForm + '\n' + COMPANY.registration + '\n' + COMPANY.address,
      },
      {
        heading: 'Directeur de la publication',
        body: COMPANY.publicationDirector,
      },
      {
        heading: 'Hébergement',
        body: COMPANY.host,
      },
      {
        heading: 'Contact',
        body: COMPANY.supportEmail,
      },
      {
        heading: 'Données de marché',
        body: "Les cours et actualités sont fournis par un prestataire tiers et sont différés. Les noms et logos " +
          "des sociétés cotées sont la propriété de leurs titulaires respectifs et ne sont utilisés qu'à des fins " +
          "d'identification.",
      },
      {
        heading: 'Nature du service',
        body: "Krezus est une application pédagogique reposant sur un portefeuille simulé. Elle ne fournit aucun " +
          "service d'investissement au sens du Code monétaire et financier et n'exécute aucun ordre de bourse.",
      },
    ],
  },
};
