import '../inspection/inspection_constants.dart';
import 'guide_preferences.dart';

enum GuidePage { home, tasks, overview, sync, profile }

const guideStageCount = 6;

const guideSampleLabel = 'DEMO / SAMPLE — For Tutorial Only';
const guideSampleTagalog = 'HALIMBAWA LAMANG — Para sa Gabay';

class GuideCopy {
  final String title;
  final String message;
  final String? details, summary;
  const GuideCopy(this.title, this.message, [this.details, this.summary]);
}

class GuideStop {
  final String id;
  final int stage;
  final GuidePage page;
  final String targetId;
  final GuideCopy english;
  final GuideCopy tagalog;

  const GuideStop(
    this.id,
    this.stage,
    this.page,
    this.targetId,
    this.english,
    this.tagalog,
  );

  GuideCopy copyFor(GuideLanguage language) =>
      language == GuideLanguage.tagalog ? tagalog : english;

  String stageTitle(GuideLanguage language) =>
      (language == GuideLanguage.tagalog
      ? const [
          'Home Dashboard',
          'Calendar at mga Aktibong Assignment',
          'My Tasks',
          'Task Overview at Inspection',
          'Sync Center',
          'Profile at Tulong',
        ]
      : const [
          'Home Dashboard',
          'Calendar & Active Assignments',
          'My Tasks',
          'Task Overview & Inspection',
          'Sync Center',
          'Profile & Help',
        ])[stage - 1];

  String progress(GuideLanguage language) {
    final stops = guideStops.where((s) => s.stage == stage).toList();
    final index = stops.indexOf(this) + 1;
    return language == GuideLanguage.tagalog
        ? 'Yugto $stage ng $guideStageCount · Paliwanag $index ng ${stops.length}'
        : 'Stage $stage of $guideStageCount · Explanation $index of ${stops.length}';
  }
}

const guideInvitationEnglish = GuideCopy(
  'Welcome to FieldSync',
  "Welcome to FieldSync! I'm your FieldSync Guide. Would you like a quick tour of the application? I'll show you where to find your inspection tasks and how the main features work.",
);
const guideInvitationTagalog = GuideCopy(
  'Maligayang pagdating sa FieldSync',
  'Maligayang pagdating sa FieldSync! Ako ang iyong FieldSync Guide. Gusto mo bang maglibot muna tayo sa application? Ipapakita ko kung saan makikita ang iyong mga inspection task at kung paano gamitin ang mahahalagang feature.',
);

/// Core inspection, sync and Profile teaching without optional shortcut lessons.
final guideStops = List<GuideStop>.unmodifiable([
  const GuideStop(
    'G02',
    1,
    GuidePage.home,
    'guide_fingerprint',
    GuideCopy(
      'Meet your fingerprint guide',
      "I'm here at the bottom right. Follow the highlights to learn the main tools without changing your work.",
      null,
      "I'm your fingerprint guide. Follow the highlights; your work stays unchanged.",
    ),
    GuideCopy(
      'Kilalanin ang fingerprint guide',
      'Nandito ako sa kanang ibaba. Sundan ang mga highlight para makilala ang mahahalagang gamit nang walang binabago sa iyong gawain.',
      null,
      'Ako ang fingerprint guide mo. Sundan ang mga highlight; walang babaguhin sa gawain mo.',
    ),
  ),
  const GuideStop(
    'G03',
    1,
    GuidePage.home,
    'home_content',
    GuideCopy(
      'Your mobile workspace',
      'Home is your starting point for assigned inspections, visit schedules, and task progress. FieldSync also helps you record field information, collect evidence, and check synchronization.',
      null,
      'Start here for assignments, schedules and progress.',
    ),
    GuideCopy(
      'Ang iyong mobile workspace',
      'Sa Home ka magsisimula para makita ang mga assignment, iskedyul ng pagbisita, at progreso ng tasks. Sa FieldSync mo rin itatala ang impormasyon sa field, ebidensiya, at status ng synchronization.',
      null,
      'Dito magsimula para sa assignment, iskedyul at progreso.',
    ),
  ),
  const GuideStop(
    'G04',
    1,
    GuidePage.home,
    'inspector_section',
    GuideCopy(
      'Account, connection and notifications',
      'Your greeting and name identify the account in use. Online or Offline shows connectivity; the bell opens relevant updates. Being online does not prove your inspection has synchronized.',
      null,
      'Check your account and connection. The bell holds updates.',
    ),
    GuideCopy(
      'Account, koneksiyon at mga abiso',
      'Makikita sa bati at pangalan kung aling account ang gamit mo. Ang Online o Offline ay para sa koneksiyon; nasa bell ang mga abiso. Hindi patunay ng matagumpay na sync ang pagiging online.',
      null,
      'Tingnan ang account, koneksiyon at mga abiso sa bell.',
    ),
  ),
  const GuideStop(
    'G05',
    1,
    GuidePage.home,
    'completion_chart',
    GuideCopy(
      'Task Status Overview',
      'Task Status Overview summarizes Scheduled, Pending, Ongoing, and Completed work. Overdue warns of a passed PO Deadline; it is not another task category.',
      'This chart uses orange for Scheduled, blue for Pending, light blue for Ongoing, green for Completed, and red for Overdue. Read the labels: these chart colors are not the same rules as task-card borders.',
      'See your workload by status. Read labels, not colors alone.',
    ),
    GuideCopy(
      'Buod ng status ng tasks',
      'Buod ng Scheduled, Pending, Ongoing, at Completed ang Task Status Overview. Babala ng lumampas na PO Deadline ang Overdue; hindi ito isa pang kategorya ng task.',
      'Kahel ang Scheduled, asul ang Pending, mapusyaw na asul ang Ongoing, berde ang Completed, at pula ang Overdue sa chart na ito. Basahin ang labels: iba ang kahulugan ng mga kulay ng border sa task cards.',
      'Tingnan ang status ng gawain. Basahin din ang labels.',
    ),
  ),
  const GuideStop(
    'G06',
    2,
    GuidePage.home,
    'calendar_section',
    GuideCopy(
      'Plan your visits',
      "Calendar helps you plan visits and see dates associated with tasks. Read the task's date label: a Visit date and a PO Deadline are different.",
      null,
      'Visit dates and PO Deadlines are different. Check the label.',
    ),
    GuideCopy(
      'Planuhin ang pagbisita',
      'Tulong ang Calendar sa pagplano ng pagbisita at pagtingin sa mga petsang kaugnay ng tasks. Basahin ang date label: magkaiba ang Visit date at PO Deadline.',
      null,
      'Magkaiba ang Visit date at PO Deadline. Basahin ang label.',
    ),
  ),
  const GuideStop(
    'G07',
    2,
    GuidePage.home,
    'assignments_section',
    GuideCopy(
      'Active Assignments',
      'Here you can see your active assignments. Each card helps you identify where you need to go, when the visit is scheduled, and what work remains.',
      null,
      'Find the active inspections that need your attention.',
    ),
    GuideCopy(
      'Mga Aktibong Assignment',
      'Dito makikita ang iyong mga aktibong assignment. Ipinapakita ng bawat card kung saan ka pupunta, kailan ang nakatakdang pagbisita, at kung anong gawain ang kailangan pang tapusin.',
      null,
      'Narito ang mga aktibong inspection na dapat asikasuhin.',
    ),
  ),
  const GuideStop(
    'G08',
    2,
    GuidePage.home,
    'assignment_card',
    GuideCopy(
      'Read an assignment card',
      'Check the applicant, location, status, date label, and saved inspection progress. You can move between cards; See All leads to My Tasks.',
      null,
      'Check the applicant, place, date and saved progress.',
    ),
    GuideCopy(
      'Basahin ang assignment card',
      'Tingnan ang aplikante, lugar, status, date label, at naka-save na progreso ng inspection. Puwedeng lumipat ng card; sa See All makikita ang My Tasks.',
      null,
      'Tingnan ang aplikante, lugar, petsa at naka-save na progreso.',
    ),
  ),
  const GuideStop(
    'G09',
    3,
    GuidePage.tasks,
    'tasks_header',
    GuideCopy(
      'Find your inspections',
      'My Tasks organizes the inspections assigned to you. In this guide, cards marked DEMO / SAMPLE are fictional examples, not new assignments.',
      null,
      'Your assigned inspections live here. Samples are labelled.',
    ),
    GuideCopy(
      'Hanapin ang mga inspection',
      'Nakaayos sa My Tasks ang mga inspection na naka-assign sa iyo. Sa gabay na ito, halimbawa lamang ang mga card na may markang DEMO / SAMPLE, hindi bagong assignment.',
      null,
      'Narito ang iyong mga inspection. May label ang halimbawa.',
    ),
  ),
  const GuideStop(
    'G10',
    3,
    GuidePage.tasks,
    'task_categories',
    GuideCopy(
      'Three main categories',
      'Pending contains work needing attention, including Scheduled visits. Ongoing contains started, unscheduled fieldwork. Completed contains finished or locally submitted work—check its delivery label too.',
      'A Scheduled task stays under Pending even after fieldwork starts; its progress is shown separately. Completed on Device is not server acceptance. Sync unverified means this device cannot confirm a final-submission receipt.',
      'Switch between Pending, Ongoing and Completed work.',
    ),
    GuideCopy(
      'Tatlong pangunahing kategorya',
      'Nasa Pending ang mga kailangang asikasuhin, kasama ang Scheduled. Nasa Ongoing ang nasimulang fieldwork na walang committed na Visit. Nasa Completed ang natapos o lokal nang naipasang gawain—basahin din ang delivery label.',
      'Nananatili sa Pending ang Scheduled kahit nasimulan na ang fieldwork; hiwalay na ipinapakita ang progreso. Hindi pa pagtanggap ng server ang Completed on Device. Sa Sync unverified, hindi makumpirma ng device ang resibo ng huling pagpapasa.',
      'Pumili sa Pending, Ongoing at Completed na gawain.',
    ),
  ),
  const GuideStop(
    'G12',
    3,
    GuidePage.tasks,
    'task_card_info',
    GuideCopy(
      'Task information and colors',
      "Check the reference, place, status, progress, and warning text. The information indicator explains the card's notices and border color—do not rely on color alone.",
      'For Scheduled visits: blue is more than three days away, orange is two to three days away, and red is tomorrow, today, or a missed visit. A passed PO Deadline makes the whole active card red. Green normally means Completed; orange may instead mean a local final submission is still awaiting server acceptance. Always read the status and receipt labels.',
      'Use the info control to understand status and warnings.',
    ),
    GuideCopy(
      'Impormasyon at kulay ng task',
      'Tingnan ang reference, lugar, status, progreso, at mga babala. Ipinapaliwanag ng information indicator ang notices at kulay ng border—huwag sa kulay lang umasa.',
      'Para sa Scheduled: asul kung lampas tatlong araw pa, kahel kung dalawa o tatlong araw na lang, at pula kung bukas, ngayon, o nalampasan na ang Visit. Kapag lumampas ang PO Deadline, pula ang buong aktibong card. Karaniwang berde ang Completed; maaari ring mangahulugan ang kahel na hinihintay pa ang pagtanggap ng server sa lokal na pagpapasa. Basahin palagi ang status at receipt labels.',
      'Nasa info control ang paliwanag ng status at mga babala.',
    ),
  ),
  const GuideStop(
    'G13',
    3,
    GuidePage.tasks,
    'task_dates',
    GuideCopy(
      'Visit date versus PO Deadline',
      'Visit date is when you plan to go. PO Deadline is the last date set by the Planning Officer. They are not the same.',
      null,
      'Your planned visit is not the Planning Officer’s deadline.',
    ),
    GuideCopy(
      'Visit date at PO Deadline',
      'Ang Visit date ay araw na balak mong pumunta. Ang PO Deadline ay huling petsang itinakda ng Planning Officer. Hindi sila pareho.',
      null,
      'Iba ang araw ng pagbisita sa deadline ng Planning Officer.',
    ),
  ),
  const GuideStop(
    'G14',
    3,
    GuidePage.tasks,
    'task_notices',
    GuideCopy(
      'Missed visits and overdue work',
      'A missed Visit may be rescheduled only while the PO Deadline is still ahead. On the deadline day, new scheduling is unavailable; after it passes, the task is Overdue.',
      'New visit choices start tomorrow and cannot go beyond a verified PO Deadline. Continue inspection work only while authorized, or coordinate with the Planning Officer. Warnings do not erase saved evidence.',
      'Read missed-visit and deadline warnings before rescheduling.',
    ),
    GuideCopy(
      'Nalampasang Visit at overdue na task',
      'Maaari lang mag-reschedule ng nalampasang Visit habang hindi pa dumarating ang PO Deadline. Sa araw ng deadline, hindi na puwedeng magtakda ng bagong Visit; pagkaraan nito, Overdue na ang task.',
      'Bukas ang pinakamaagang bagong Visit at hindi ito maaaring lumampas sa nakumpirmang PO Deadline. Ipagpatuloy lamang ang inspection kung awtorisado ka pa, o makipag-ugnayan sa Planning Officer. Hindi binubura ng babala ang naka-save na ebidensiya.',
      'Basahin ang babala ng Visit at deadline bago mag-reschedule.',
    ),
  ),
  const GuideStop(
    'G15',
    3,
    GuidePage.tasks,
    'guide_task_card',
    GuideCopy(
      'Search, filter and explore a task',
      "Use search and the available barangay, date, and urgency filters to locate a task. Let's explore its details and the six inspection steps without changing your work.",
      null,
      'Explore this task safely. Nothing will be saved or started.',
    ),
    GuideCopy(
      'Maghanap, mag-filter at suriin ang task',
      'Gamitin ang search at mga filter ng barangay, petsa, at urgency para mahanap ang task. Tingnan natin ang mga detalye at anim na inspection steps nang walang binabago sa iyong gawain.',
      null,
      'Suriin ang task. Walang ise-save o sisimulang inspection.',
    ),
  ),
  const GuideStop(
    'G16',
    4,
    GuidePage.overview,
    'overview_header',
    GuideCopy(
      'Task Overview',
      'Task Overview brings together site details, dates, instructions, and inspection status. This walkthrough is read-only and cannot start a real inspection.',
      null,
      'Review the selected inspection’s details and saved status.',
    ),
    GuideCopy(
      'Buod ng inspection',
      'Magkakasama sa Task Overview ang detalye ng site, mga petsa, tagubilin, at status. Read-only ang gabay na ito at hindi ito makapagsisimula ng totoong inspection.',
      null,
      'Suriin ang detalye at naka-save na status ng inspection.',
    ),
  ),
  const GuideStop(
    'G17',
    4,
    GuidePage.overview,
    'inspection_protocol',
    GuideCopy(
      'The six-step protocol',
      'Complete Step 1, then Step 2. After GPS verification, Steps 3, 4, and 5 can be completed independently in any order. Step 6 opens after all required work is complete.',
      null,
      'Finish 1, then 2. Steps 3–5 are independent; review comes last.',
    ),
    GuideCopy(
      'Ang anim na hakbang',
      'Tapusin muna ang Step 1, saka ang Step 2. Pagkatapos ng GPS verification, puwedeng gawin ang Steps 3, 4, at 5 nang hiwa-hiwalay at sa kahit anong ayos. Magbubukas ang Step 6 kapag kumpleto na ang kailangan.',
      null,
      'Unahin ang 1 at 2. Hiwalay ang 3–5; huli ang review.',
    ),
  ),
  const GuideStop(
    'G18',
    4,
    GuidePage.overview,
    'step_1',
    GuideCopy(
      'Site Verification',
      "Site Verification uses the assigned task's map to identify the target site. Check its markers and available route guidance; a map is not a surveyed property boundary.",
      null,
      'Orient yourself using the assigned site and saved map data.',
    ),
    GuideCopy(
      'Pagtiyak sa site',
      'Sa Site Verification, ginagamit ang mapa ng task para matukoy ang nakatalagang site. Tingnan ang markers at available na gabay sa ruta; hindi ito survey ng hangganan ng lupa.',
      null,
      'Gamitin ang site at naka-save na mapa para sa oryentasyon.',
    ),
  ),
  GuideStop(
    'G19',
    4,
    GuidePage.overview,
    'step_2',
    GuideCopy(
      'GPS Verification',
      "GPS Verification checks your phone's location relative to the target site. Being nearby is not enough: the location reading must also be accurate and recent.",
      'In the reviewed source, verification requires a valid location within ${siteVerificationDistanceThresholdMeters.toStringAsFixed(0)}m, reported accuracy greater than zero and at most ${kReliableFixMaxAccuracyMeters.toStringAsFixed(0)}m, and a fix no older than ${kReliableFixMaxAge.inSeconds} seconds or more than ${kReliableFixFutureSkew.inSeconds} seconds in the future. These are app validation rules, not a guarantee of survey accuracy.',
      'A real check needs a nearby, accurate and fresh GPS fix.',
    ),
    GuideCopy(
      'Pagtiyak sa lokasyon',
      'Sinusuri ng GPS Verification ang lokasyon ng phone kaugnay ng target na site. Hindi sapat na malapit ka lang: kailangan ding maayos at bago ang location reading.',
      'Sa sinuring source, kailangan ang valid na lokasyong nasa loob ng ${siteVerificationDistanceThresholdMeters.toStringAsFixed(0)}m, accuracy na lampas zero at hindi hihigit sa ${kReliableFixMaxAccuracyMeters.toStringAsFixed(0)}m, at reading na hindi lalampas sa ${kReliableFixMaxAge.inSeconds} segundo ang tanda o ${kReliableFixFutureSkew.inSeconds} segundo sa hinaharap. Mga validation rule ito ng app, hindi garantiya ng katumpakan ng survey.',
      'Kailangan ang malapit, maayos at bagong GPS reading.',
    ),
  ),
  const GuideStop(
    'G20',
    4,
    GuidePage.overview,
    'step_3',
    GuideCopy(
      'Photographic Evidence',
      'Photographic Evidence documents actual site conditions. Review saved evidence where available; this guide will not open the camera or change your photos.',
      null,
      'Review site evidence here. The tour never opens your camera.',
    ),
    GuideCopy(
      'Larawang ebidensiya',
      'Itinatala ng Photographic Evidence ang aktuwal na kalagayan ng site. Makikita ang naka-save na ebidensiya kung mayroon; hindi bubuksan ang camera o babaguhin ang mga larawan.',
      null,
      'Dito ang ebidensiya ng site. Hindi bubuksan ang camera.',
    ),
  ),
  const GuideStop(
    'G21',
    4,
    GuidePage.overview,
    'step_4',
    GuideCopy(
      'Zoning Checklist',
      'Read each Zoning Checklist item and record what you actually observed. Do not check an item you have not verified.',
      null,
      'Check only the conditions you actually verified on-site.',
    ),
    GuideCopy(
      'Checklist ng obserbasyon',
      'Basahin ang bawat item sa Zoning Checklist at itala ang aktuwal mong nakita. Huwag mag-check ng hindi mo pa nasusuri.',
      null,
      'I-check lamang ang aktuwal mong natiyak sa site.',
    ),
  ),
  const GuideStop(
    'G22',
    4,
    GuidePage.overview,
    'step_5',
    GuideCopy(
      'Field Findings',
      'Field Findings records your notes and observations. Explain discrepancies clearly and include relevant recommendations based on what you found.',
      null,
      'Record observations, explain issues and recommend action.',
    ),
    GuideCopy(
      'Mga natuklasan sa field',
      'Sa Field Findings itinatala ang notes at mga napansin mo. Ipaliwanag nang malinaw ang pagkakaiba o problema at ang kaugnay na rekomendasyon batay sa nakita mo.',
      null,
      'Itala ang nakita, mga problema at rekomendasyon.',
    ),
  ),
  const GuideStop(
    'G23',
    4,
    GuidePage.overview,
    'step_6',
    GuideCopy(
      'Review & Submit',
      'Review all required information and evidence before submission. This walkthrough is read-only: no real inspection will be sent.',
      null,
      'Review before submitting. This tour sends nothing.',
    ),
    GuideCopy(
      'Suriin bago ipasa',
      'Suriin muna ang lahat ng kailangang impormasyon at ebidensiya bago magpasa. Read-only ang gabay: walang totoong inspection na ipapadala.',
      null,
      'Suriin bago ipasa. Walang ipapadala ang gabay na ito.',
    ),
  ),
  const GuideStop(
    'G24',
    4,
    GuidePage.overview,
    'evidence_details',
    GuideCopy(
      'Evidence, details and returning',
      "Evidence attachments includes site photos and any Site Location Reference; Application Details identifies the application and location. Let's return to the main navigation without saving this example.",
      null,
      'Review attachments and application details without saving.',
    ),
    GuideCopy(
      'Ebidensiya, detalye at pagbalik',
      'Nasa Evidence attachments ang site photos at Site Location Reference kung mayroon; nasa Application Details ang detalye ng application at lugar. Balik tayo sa main navigation nang walang sine-save na halimbawa.',
      null,
      'Suriin ang ebidensiya at detalye nang walang sine-save.',
    ),
  ),
  const GuideStop(
    'G32',
    5,
    GuidePage.sync,
    'sync_summary',
    GuideCopy(
      'Offline work and synchronization',
      'When internet access is unavailable, supported inspection changes may remain saved on your device. Sync Center helps you see what still needs to be transmitted.',
      null,
      'See what is saved locally and still waiting to send.',
    ),
    GuideCopy(
      'Offline na gawain at synchronization',
      'Kapag walang internet, maaaring manatiling naka-save sa device ang mga suportadong pagbabago sa inspection. Sa Sync Center, makikita mo kung alin ang kailangan pang maipadala.',
      null,
      'Tingnan ang naka-save sa device at naghihintay maipadala.',
    ),
  ),
  const GuideStop(
    'G33',
    5,
    GuidePage.sync,
    'sync_waiting',
    GuideCopy(
      'Waiting to sync',
      'Waiting to sync shows locally saved updates that have not finished sending. Only items explicitly marked SAMPLE are fictional examples.',
      null,
      'These updates are on your device, not yet confirmed sent.',
    ),
    GuideCopy(
      'Naghihintay na maipadala',
      'Nasa Waiting to sync ang mga lokal na update na hindi pa tapos maipadala. Halimbawa lamang ang mga item na malinaw na may markang SAMPLE.',
      null,
      'Nasa device ang mga update; hindi pa kumpirmadong naipadala.',
    ),
  ),
  const GuideStop(
    'G34',
    5,
    GuidePage.sync,
    'sync_attention_storage',
    GuideCopy(
      'Attention, retries and storage',
      'Read errors and retry guidance before using Sync now in normal work. Offline storage shows cached information; this guide will not sync, resolve a conflict, or clear evidence.',
      'Some updates may be failed, paused, or in conflict and need attention. If encrypted storage cannot be read, do not clear app data; contact your administrator. A cache count is not proof of server receipt.',
      'Read errors first. The tour never syncs or clears evidence.',
    ),
    GuideCopy(
      'Mga kailangang asikasuhin at storage',
      'Basahin ang error at gabay sa retry bago gamitin ang Sync now sa normal na trabaho. Nasa Offline storage ang naka-cache na impormasyon; walang isi-sync, aayusing conflict, o buburahing ebidensiya ang gabay.',
      'Maaaring failed, paused, o may conflict ang ilang update at kailangan itong asikasuhin. Kung hindi mabasa ang encrypted storage, huwag i-clear ang app data; makipag-ugnayan sa administrator. Hindi patunay ng pagtanggap ng server ang bilang ng cache.',
      'Basahin muna ang error. Walang isi-sync o buburahin dito.',
    ),
  ),
  const GuideStop(
    'G35',
    5,
    GuidePage.sync,
    'sync_received',
    GuideCopy(
      'Saved, synchronized and reviewed',
      'Saved on this device, accepted by the server, and reviewed by the Planning Officer are different facts. Successful synchronization does not prove the PO has reviewed your report.',
      null,
      'A server receipt does not mean the Planning Officer reviewed it.',
    ),
    GuideCopy(
      'Naka-save, na-sync at na-review',
      'Magkaiba ang naka-save sa device, natanggap ng server, at na-review ng Planning Officer. Hindi patunay ang matagumpay na sync na nabasa na ng PO ang report.',
      null,
      'Ang resibo ng server ay hindi pa review ng Planning Officer.',
    ),
  ),
  const GuideStop(
    'G36',
    6,
    GuidePage.profile,
    'profile_identity',
    GuideCopy(
      'Your profile',
      'Profile brings your account information, inspection summary, settings, performance and help together. Check that you are using the correct inspector account.',
      null,
      'Your account, settings, performance and help come together here.',
    ),
    GuideCopy(
      'Ang iyong profile',
      'Magkakasama sa Profile ang impormasyon ng account, buod ng inspection, settings, performance at tulong. Tiyaking tamang inspector account ang gamit mo.',
      null,
      'Dito magkakasama ang account, settings, performance at tulong.',
    ),
  ),
  const GuideStop(
    'G36-summary',
    6,
    GuidePage.profile,
    'profile_summary',
    GuideCopy(
      'Your inspection summary',
      'These totals summarize your recorded Pending / Ongoing and Completed inspections. They help you see your workload; a completed count alone does not confirm server acceptance.',
      null,
      'See your remaining workload and recorded completed inspections.',
    ),
    GuideCopy(
      'Buod ng iyong inspection',
      'Buod ito ng naitalang Pending / Ongoing at Completed inspections. Tulong ito sa pagtingin ng gawain; hindi patunay ng pagtanggap ng server ang bilang ng Completed lamang.',
      null,
      'Tingnan ang natitirang gawain at naitalang completed inspections.',
    ),
  ),
  const GuideStop(
    'G37',
    6,
    GuidePage.profile,
    'profile_analytics',
    GuideCopy(
      'Performance Analytics',
      'Performance Analytics gives you a closer look at recorded work. The current views include Bars, Activity, Gauge, and Sectors, with Week and Month options.',
      null,
      'Review recorded activity and spot work patterns by week or month.',
    ),
    GuideCopy(
      'Buod ng mga nagawa sa inspection',
      'Mas detalyadong buod ng naitalang gawain ang Performance Analytics. May Bars, Activity, Gauge, at Sectors, at pagpipiliang Week o Month.',
      null,
      'Balikan ang naitalang gawain at progreso kada linggo o buwan.',
    ),
  ),
  const GuideStop(
    'G38',
    6,
    GuidePage.profile,
    'profile_security',
    GuideCopy(
      'Security & Protection',
      'Security & Protection contains supported controls such as biometric login and auto-lock. Your existing protection stays active throughout this guide.',
      null,
      'Your biometric and auto-lock protections remain active.',
    ),
    GuideCopy(
      'Seguridad at proteksiyon',
      'Nasa Security & Protection ang mga suportadong setting gaya ng biometric login at auto-lock. Mananatiling aktibo ang kasalukuyan mong proteksiyon habang ginagamit ang gabay.',
      null,
      'Mananatiling aktibo ang biometric at auto-lock protection.',
    ),
  ),
  const GuideStop(
    'G39',
    6,
    GuidePage.profile,
    'profile_help',
    GuideCopy(
      'Help & FAQ',
      'Find answers to common questions and practical guidance about FieldSync features in Help & FAQ.',
      null,
      'Find answers and practical guidance about FieldSync features.',
    ),
    GuideCopy(
      'Tulong at FAQ',
      'Sa Help & FAQ makikita ang sagot sa karaniwang tanong at praktikal na gabay sa mga feature ng FieldSync.',
      null,
      'Dito ang sagot sa mga tanong at praktikal na gabay sa feature.',
    ),
  ),
  const GuideStop(
    'G39-support',
    6,
    GuidePage.profile,
    'profile_support',
    GuideCopy(
      'Support Desk',
      'Request assistance for application concerns here. Technical Issue is for problems with FieldSync itself; Application Support is for an assigned task or application needing clarification. My Reports lets you check reports and follow up. This tour submits nothing.',
      null,
      'Technical Issue: app problems. Application Support: task concerns. My Reports: check and follow up.',
    ),
    GuideCopy(
      'Support Desk',
      'Dito humingi ng tulong sa paggamit ng application. Technical Issue para sa problema sa FieldSync; Application Support para sa tanong o paglilinaw sa naka-assign na task o application. Sa My Reports makikita at masusubaybayan ang mga report. Walang ipapasa ang tour.',
      null,
      'Technical Issue: problema sa app. Application Support: concern sa task. My Reports: tingnan at i-follow up ang report.',
    ),
  ),
  const GuideStop(
    'G39-policies',
    6,
    GuidePage.profile,
    'profile_policies',
    GuideCopy(
      'Your policies and information',
      'Terms & Conditions explains rules and responsibilities. Privacy Policy explains how relevant personal information is handled and protected. Cookie & Storage Policy covers applicable storage practices and locally saved information. Each has its own page to review whenever needed.',
      null,
      'Rules of use, personal-data protection and local storage: each policy has its own page for later review.',
    ),
    GuideCopy(
      'Mga patakaran at impormasyon',
      'Nasa Terms & Conditions ang tuntunin at pananagutan. Nasa Privacy Policy kung paano hinahawakan at pinoprotektahan ang personal na impormasyon. Nasa Cookie & Storage Policy ang storage practices at lokal na impormasyon. May sariling pahina ang bawat isa na mababalikan anumang oras.',
      null,
      'Mga tuntunin, proteksiyon ng personal na datos at local storage: may sariling pahina ang bawat patakaran.',
    ),
  ),
  const GuideStop(
    'G39-about',
    6,
    GuidePage.profile,
    'profile_about',
    GuideCopy(
      'About iMAPS',
      'FieldSync is part of the larger iMAPS system. About iMAPS explains its purpose, background and other application information.',
      null,
      'Learn how FieldSync fits into iMAPS, its purpose and application information.',
    ),
    GuideCopy(
      'Tungkol sa iMAPS',
      'Bahagi ang FieldSync ng mas malawak na iMAPS system. Nasa About iMAPS ang layunin, background at iba pang impormasyon ng application.',
      null,
      'Alamin ang papel ng FieldSync sa iMAPS, layunin at impormasyon ng application.',
    ),
  ),
  const GuideStop(
    'G41',
    6,
    GuidePage.profile,
    'profile_identity',
    GuideCopy(
      "You're all set",
      "You're ready to manage inspections and find help. Your saved work is unchanged.",
      null,
      "You're ready to manage inspections and find help. Your saved work is unchanged.",
    ),
    GuideCopy(
      'Ayos, handa ka na!',
      'Handa ka nang mag-asikaso ng inspections at humingi ng tulong. Walang nabago sa naka-save mong gawain.',
      null,
      'Handa ka nang mag-asikaso ng inspections at humingi ng tulong. Walang nabago sa naka-save mong gawain.',
    ),
  ),
]);

class GuideLabels {
  final GuideLanguage language;
  const GuideLabels(this.language);
  bool get isTagalog => language == GuideLanguage.tagalog;
  String _pick(String english, String tagalog) => isTagalog ? tagalog : english;

  String get start => _pick('Start Tour', 'Simulan ang Gabay');
  String get notNow => _pick('Not Now', 'Mamaya Na');
  String get back => _pick('Back', 'Balik');
  String get next => _pick('Next', 'Susunod');
  String get skip => _pick('Skip Tour', 'Laktawan ang Gabay');
  String get done => _pick('Done', 'Tapos Na');
  String get replay => _pick('Replay Tour', 'Ulitin ang Gabay');
  String get chooseLanguage => _pick('Choose language', 'Piliin ang wika');
  String get moreDetails => _pick('More details', 'Karagdagang detalye');
  String get close => _pick('Close', 'Isara');
  String get navigation => _pick(
    'Tap the left side to go back or the right side to continue. You can also use Back and Next.',
    'Pindutin ang kaliwang bahagi para bumalik o ang kanan para magpatuloy. Maaari ring gamitin ang Balik at Susunod.',
  );
  String get noAssignments => _pick(
    "You don't have an assignment to display here. I'll show a clearly marked sample so you can learn the layout.",
    'Wala pang assignment na maipapakita rito. Magpapakita muna ako ng malinaw na minarkahang halimbawa para makita mo ang layout.',
  );
  String get emptyTasks => _pick(
    'This is only an example. It is not assigned to your account and cannot change an inspection.',
    'Halimbawa lamang ito. Hindi ito assignment sa account mo at wala itong mababagong inspection.',
  );
  String get mapSample => _pick(
    'This is a sample diagram, not a live map or GPS verification.',
    'Halimbawang diagram lamang ito, hindi live na mapa o GPS verification.',
  );
  String get evidenceSample => _pick(
    'These are fictional placeholders. In a real inspection, record your own site evidence and observations.',
    'Mga kathang halimbawang placeholder lang ito. Sa totoong inspection, sarili mong ebidensiya at obserbasyon ang itatala.',
  );
  String get syncSample => _pick(
    'This example shows what a waiting or received status can look like. It is not an actual update or receipt.',
    'Ipinapakita ng halimbawa ang posibleng hitsura ng naghihintay o natanggap na update. Hindi ito totoong update o resibo.',
  );
  String get noMetrics => _pick(
    'Any example figures are labelled SAMPLE and are not your performance record.',
    'May markang SAMPLE ang anumang halimbawang bilang at hindi iyon tala ng mga nagawa mo.',
  );
  String get welcomeBack => _pick(
    'Welcome back. Continue the guide when you\'re ready.',
    'Nandito ka na ulit. Ituloy ang gabay kapag handa ka na.',
  );
  String get pageIntroduction => _pick(
    "Learn the application's tools through an interactive walkthrough.",
    'Alamin ang mga gamit ng application sa pamamagitan ng interaktibong gabay.',
  );
  String get exploreHeading =>
      _pick("What you'll explore", 'Mga matututuhan mo');
  String get exploreBody =>
      'Home · My Tasks · Task Overview · Sync Center · Profile';
  String get navigationHeading => _pick('How to navigate', 'Paano magpatuloy');
  String get examplesHeading =>
      _pick('Safe learning examples', 'Ligtas na mga halimbawa');
  String get examplesBody => _pick(
    'The guide may display fictional examples marked DEMO / SAMPLE — For Tutorial Only. They are not inspection records.',
    'Maaaring magpakita ang gabay ng kathang halimbawang may markang DEMO / SAMPLE — For Tutorial Only. Hindi mga inspection record ang mga ito.',
  );
  String get safety => _pick(
    'You can skip or finish without modifying inspection records. No real GPS, camera, synchronization, or submission action is performed by the tour.',
    'Maaaring laktawan o tapusin ang gabay nang walang binabagong inspection record. Walang totoong GPS, camera, synchronization, o pagpapasa na gagawin ang tour.',
  );
  String get replayLanguageNote => _pick(
    'You can change the language before every replay.',
    'Puwedeng palitan ang wika bago ulitin ang gabay.',
  );
}
