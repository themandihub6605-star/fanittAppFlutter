import 'package:flutter/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Single source of icons (Phosphor, regular = outline weight).
/// Filled variants are used only for selected navigation items.
abstract final class AppIcons {
  // Navigation
  static const IconData home = PhosphorIconsRegular.house;
  static const IconData homeFilled = PhosphorIconsFill.house;
  static const IconData store = PhosphorIconsRegular.storefront;
  static const IconData storeFilled = PhosphorIconsFill.storefront;
  static const IconData library = PhosphorIconsRegular.books;
  static const IconData libraryFilled = PhosphorIconsFill.books;
  static const IconData package = PhosphorIconsRegular.package;
  static const IconData download = PhosphorIconsRegular.downloadSimple;
  static const IconData idCard = PhosphorIconsRegular.identificationCard;
  static const IconData fileText = PhosphorIconsRegular.fileText;
  static const IconData lightning = PhosphorIconsRegular.lightning;
  static const IconData chartLine = PhosphorIconsRegular.chartLineUp;
  static const IconData campaigns = PhosphorIconsRegular.megaphone;
  static const IconData campaignsFilled = PhosphorIconsFill.megaphone;
  static const IconData megaphoneAlt = PhosphorIconsRegular.megaphoneSimple;
  static const IconData messages = PhosphorIconsRegular.chatCircleDots;
  static const IconData messagesFilled = PhosphorIconsFill.chatCircleDots;
  static const IconData feed = PhosphorIconsRegular.images;
  static const IconData feedFilled = PhosphorIconsFill.images;
  static const IconData wallet = PhosphorIconsRegular.wallet;
  static const IconData walletFilled = PhosphorIconsFill.wallet;
  static const IconData creators = PhosphorIconsRegular.usersThree;
  static const IconData creatorsFilled = PhosphorIconsFill.usersThree;
  static const IconData account = PhosphorIconsRegular.userCircle;
  static const IconData accountFilled = PhosphorIconsFill.userCircle;
  static const IconData network = PhosphorIconsRegular.shareNetwork;
  static const IconData networkFilled = PhosphorIconsFill.shareNetwork;
  static const IconData dashboard = PhosphorIconsRegular.squaresFour;
  static const IconData dashboardFilled = PhosphorIconsFill.squaresFour;

  // Roles
  static const IconData creator = PhosphorIconsRegular.sparkle;
  static const IconData brand = PhosphorIconsRegular.storefront;
  static const IconData agency = PhosphorIconsRegular.buildings;

  // Forms & actions
  static const IconData mail = PhosphorIconsRegular.envelopeSimple;
  static const IconData lock = PhosphorIconsRegular.lock;
  static const IconData eye = PhosphorIconsRegular.eye;
  static const IconData eyeOff = PhosphorIconsRegular.eyeSlash;
  static const IconData user = PhosphorIconsRegular.user;
  static const IconData phone = PhosphorIconsRegular.phone;
  static const IconData gift = PhosphorIconsRegular.gift;
  static const IconData google = PhosphorIconsRegular.googleLogo;
  static const IconData back = PhosphorIconsRegular.arrowLeft;
  static const IconData chevronRight = PhosphorIconsRegular.caretRight;
  static const IconData arrowRightSimple = PhosphorIconsRegular.arrowRight;
  static const IconData copy = PhosphorIconsRegular.copy;
  static const IconData signOut = PhosphorIconsRegular.signOut;
  static const IconData refresh = PhosphorIconsRegular.arrowClockwise;
  static const IconData arrowCircleUp = PhosphorIconsRegular.arrowCircleUp;
  static const IconData gear = PhosphorIconsRegular.gearSix;
  static const IconData pencil = PhosphorIconsRegular.pencilSimple;
  static const IconData dotsThree = PhosphorIconsRegular.dotsThree;

  // Status
  static const IconData shieldCheck = PhosphorIconsRegular.shieldCheck;
  static const IconData sealCheck = PhosphorIconsRegular.sealCheck;
  static const IconData handshake = PhosphorIconsRegular.handshake;
  static const IconData hourglass = PhosphorIconsRegular.hourglassMedium;
  static const IconData xCircle = PhosphorIconsRegular.xCircle;
  static const IconData checkCircle = PhosphorIconsRegular.checkCircle;
  static const IconData warning = PhosphorIconsRegular.warningCircle;
  static const IconData info = PhosphorIconsRegular.info;
  static const IconData envelopeOpen = PhosphorIconsRegular.envelopeOpen;
  static const IconData wifiOff = PhosphorIconsRegular.wifiSlash;

  // Content & actions
  static const IconData image = PhosphorIconsRegular.image;
  static const IconData video = PhosphorIconsRegular.filmStrip;
  static const IconData play = PhosphorIconsFill.play;
  static const IconData pause = PhosphorIconsFill.pause;
  static const IconData playCircle = PhosphorIconsRegular.playCircle;
  static const IconData pauseCircle = PhosphorIconsRegular.pauseCircle;
  static const IconData speakerOn = PhosphorIconsRegular.speakerHigh;
  static const IconData speakerOff = PhosphorIconsRegular.speakerSlash;
  static const IconData videoCamera = PhosphorIconsRegular.videoCamera;
  static const IconData broadcast = PhosphorIconsRegular.broadcast;
  static const IconData camera = PhosphorIconsRegular.camera;
  static const IconData plus = PhosphorIconsRegular.plus;
  static const IconData minus = PhosphorIconsRegular.minus;
  static const IconData close = PhosphorIconsRegular.x;
  static const IconData check = PhosphorIconsRegular.check;
  static const IconData checks = PhosphorIconsRegular.checks;
  static const IconData caretDown = PhosphorIconsRegular.caretDown;
  static const IconData trash = PhosphorIconsRegular.trash;
  static const IconData upload = PhosphorIconsRegular.uploadSimple;
  static const IconData file = PhosphorIconsRegular.file;
  static const IconData paperclip = PhosphorIconsRegular.paperclip;
  static const IconData link = PhosphorIconsRegular.link;
  static const IconData send = PhosphorIconsRegular.paperPlaneRight;
  static const IconData paperPlane = PhosphorIconsRegular.paperPlaneTilt;
  static const IconData search = PhosphorIconsRegular.magnifyingGlass;
  static const IconData sliders = PhosphorIconsRegular.slidersHorizontal;
  static const IconData crop = PhosphorIconsRegular.crop;
  static const IconData chevronDown = PhosphorIconsRegular.caretDown;
  static const IconData bookmark = PhosphorIconsRegular.bookmarkSimple;
  static const IconData bookmarkFilled = PhosphorIconsFill.bookmarkSimple;
  static const IconData bell = PhosphorIconsRegular.bell;
  static const IconData bellSlash = PhosphorIconsRegular.bellSlash;
  static const IconData pushPin = PhosphorIconsRegular.pushPin;
  static const IconData chartBar = PhosphorIconsRegular.chartBar;
  static const IconData heart = PhosphorIconsRegular.heart;
  static const IconData heartFilled = PhosphorIconsFill.heart;
  static const IconData star = PhosphorIconsRegular.star;
  static const IconData starFilled = PhosphorIconsFill.star;
  static const IconData userPlus = PhosphorIconsRegular.userPlus;
  static const IconData users = PhosphorIconsRegular.users;
  static const IconData shareNetwork = PhosphorIconsRegular.shareNetwork;
  static const IconData share = PhosphorIconsRegular.shareFat;
  static const IconData translate = PhosphorIconsRegular.translate;

  // Money & places
  static const IconData rupee = PhosphorIconsRegular.currencyInr;
  static const IconData bank = PhosphorIconsRegular.bank;
  static const IconData receipt = PhosphorIconsRegular.receipt;
  static const IconData arrowDownLeft = PhosphorIconsRegular.arrowDownLeft;
  static const IconData arrowUpRight = PhosphorIconsRegular.arrowUpRight;
  static const IconData crown = PhosphorIconsRegular.crownSimple;
  static const IconData sparkle = PhosphorIconsRegular.sparkle;
  static const IconData mapPin = PhosphorIconsRegular.mapPin;
  static const IconData globe = PhosphorIconsRegular.globe;
  static const IconData calendar = PhosphorIconsRegular.calendarBlank;
  static const IconData clock = PhosphorIconsRegular.clock;
  static const IconData at = PhosphorIconsRegular.at;

  // Socials
  static const IconData instagram = PhosphorIconsRegular.instagramLogo;
  static const IconData youtube = PhosphorIconsRegular.youtubeLogo;
  static const IconData linkedin = PhosphorIconsRegular.linkedinLogo;
}