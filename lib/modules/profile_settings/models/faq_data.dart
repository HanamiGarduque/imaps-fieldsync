import 'package:flutter/material.dart';
import 'faq_item.dart';

class FaqData {
  static const List<FaqCategory> categories = [
    // 1. TASKS & COLORS
    FaqCategory(
      titleEn: 'Tasks & Colors',
      titleTl: 'Mga Task at Kulay',
      icon: Icons.palette_outlined,
      items: [
        FaqItem(
          questionEn: 'Why is my task blue?',
          questionTl: 'Bakit kulay blue ang task ko?',
          answerEn:
              'Blue means the task is in its normal priority state. It does not mean the task is completed.',
          answerTl:
              'Ang kulay blue ay nangangahulugang normal ang priority ng task. Hindi ibig sabihin nito na completed na ang task.',
        ),
        FaqItem(
          questionEn: 'Why did my task turn orange?',
          questionTl: 'Bakit naging orange ang task ko?',
          answerEn:
              'Orange means the scheduled visit date is getting close. It is a warning to help you prepare for the upcoming visit.',
          answerTl:
              'Ang kulay orange ay nangangahulugang papalapit na ang nakatakdang visit date. Babala ito upang makapaghanda ka sa iyong pagbisita.',
        ),
        FaqItem(
          questionEn: 'Why did my task turn red?',
          questionTl: 'Bakit naging red ang task ko?',
          answerEn:
              'Red means the task needs urgent attention. This can happen when the scheduled visit is very close or when the administrative deadline has already passed.',
          answerTl:
              'Ang kulay red ay nangangahulugang kailangan ng agarang aksyon. Nangyayari ito kapag napakalapit na ng scheduled visit o kaya ay lumagpas na ang administrative deadline.',
        ),
        FaqItem(
          questionEn: 'What does "Available Anytime" mean?',
          questionTl: 'Ano ang ibig sabihin ng "Available Anytime"?',
          answerEn:
              'It means the MPDO assigned the inspection to you, but you have not chosen a specific visit date yet. You may visit the site before the administrative deadline.',
          answerTl:
              'Ibig sabihin nito ay itinalaga sa iyo ng MPDO ang inspection, ngunit hindi ka pa pumipili ng tiyak na visit date. Maaari mong bisitahin ang site bago sumapit ang administrative deadline.',
        ),
        FaqItem(
          questionEn: 'What is the difference between Visit Date and Deadline?',
          questionTl: 'Ano ang pagkakaiba ng Visit Date at Deadline?',
          answerEn:
              'The Visit Date is the date you chose for your site visit.\n\nThe Deadline is the final date set by the MPDO for completing the inspection.',
          answerTl:
              'Ang Visit Date ay ang petsang ikaw mismo ang pumili para sa iyong pagpunta sa site.\n\nAng Deadline ay ang huling petsa na itinakda ng MPDO para matapos ang inspection.',
        ),
        FaqItem(
          questionEn: 'What dates can I choose when scheduling a visit?',
          questionTl:
              'Anong mga petsa ang maaari kong piliin sa pag-schedule ng pagbisita?',
          answerEn:
              'You can choose any date starting from tomorrow up to the administrative deadline. The app does not allow scheduling on the same day or past the deadline.',
          answerTl:
              'Maaari kang pumili ng alinmang petsa simula bukas hanggang sa administrative deadline. Hindi pinapayagan ng app ang same-day schedule o ang pagpili ng petsang lampas sa deadline.',
        ),
        FaqItem(
          questionEn: 'Why can\'t I schedule a visit for today?',
          questionTl:
              'Bakit hindi ako maaaring mag-schedule ng pagbisita para sa araw na ito?',
          answerEn:
              'The app\'s scheduling calendar starts from tomorrow up to the administrative deadline. If you want to inspect a site today, you can perform the inspection directly without scheduling ahead.',
          answerTl:
              'Ang kalendaryo sa pag-schedule ng app ay nakatakdang magsimula bukas hanggang sa administrative deadline. Kung nais mong mag-inspeksyon ngayon, maaari mong direktang isagawa ang inspection nang hindi na kailangang mag-schedule.',
        ),
        FaqItem(
          questionEn: 'Can I reschedule?',
          questionTl: 'Maaari ba akong mag-reschedule?',
          answerEn:
              'Yes. A scheduled inspection can be rescheduled again as long as it has not been finally submitted. The new visit date replaces the previous scheduled date.',
          answerTl:
              'Oo. Maaaring i-reschedule muli ang isang scheduled inspection hangga\'t hindi pa ito pinal na naisusumite. Papalitan ng bagong visit date ang dating petsa.',
        ),
        FaqItem(
          questionEn: 'What does "For Reschedule" mean?',
          questionTl: 'Ano ang ibig sabihin ng "For Reschedule"?',
          answerEn:
              'It means your chosen visit date has passed, but the administrative deadline is still active. You should pick a new valid visit date as soon as possible.',
          answerTl:
              'Ibig sabihin nito ay lumipas na ang napili mong petsa ng pagbisita, ngunit hindi pa lumalampas ang administrative deadline. Pumili agad ng bagong petsa ng pagbisita.',
        ),
        FaqItem(
          questionEn: 'What does "Modified" mean?',
          questionTl: 'Ano ang ibig sabihin ng "Modified"?',
          answerEn:
              'Modified means an inspection that was already completed has been reopened and actually changed during Rework.',
          answerTl:
              'Ang Modified ay nangangahulugang ang isang completed na inspection ay muling binuksan at may aktwal na binago habang nasa Rework.',
        ),
        FaqItem(
          questionEn: 'What does Overdue mean?',
          questionTl: 'Ano ang ibig sabihin ng Overdue?',
          answerEn:
              'Overdue means the administrative deadline has already passed and the inspection has not yet been completed.',
          answerTl:
              'Ang Overdue ay nangangahulugang lumagpas na ang administrative deadline at hindi pa natatapos ang inspection.',
        ),
      ],
    ),
    // 2. SITE VERIFICATION
    FaqCategory(
      titleEn: 'Site Verification',
      titleTl: 'Pag-verify sa Site',
      icon: Icons.map_outlined,
      items: [
        FaqItem(
          questionEn: 'What is Step 1 for?',
          questionTl: 'Para saan ang Step 1?',
          answerEn:
              'Step 1 helps you locate and orient yourself toward the inspection site.',
          answerTl:
              'Ang Step 1 ay tumutulong sa iyo upang matukoy ang lokasyon at direksyon papunta sa inspection site.',
        ),
        FaqItem(
          questionEn: 'What is the red pin?',
          questionTl: 'Ano ang red pin?',
          answerEn:
              'The red pin shows the target parcel or inspection site.',
          answerTl:
              'Ipinapakita ng red pin ang target parcel o ang lokasyon ng inspection site.',
        ),
        FaqItem(
          questionEn: 'What is the blue "You are here" marker?',
          questionTl: 'Ano ang blue "You are here" marker?',
          answerEn:
              'It shows your current GPS location.',
          answerTl:
              'Ipinapakita nito ang iyong kasalukuyang GPS location.',
        ),
        FaqItem(
          questionEn: 'What does the blue line mean?',
          questionTl: 'Ano ang ibig sabihin ng blue line?',
          answerEn:
              'The blue line is a route preview that helps you understand the path from your current location toward the site. It is not a turn-by-turn navigation system.\n\nWhen available, the app can show a road-based route. If that route is unavailable, the app can use a simpler guide line.',
          answerTl:
              'Ang blue line ay isang route preview na tumutulong upang maunawaan ang daan mula sa iyong kinalalagyan patungo sa site. Hindi ito turn-by-turn navigation system.\n\nKapag may koneksyon, maaaring magpakita ang app ng rutang nakabatay sa kalsada. Kung hindi ito available, gagamit ang app ng mas simpleng guide line.',
        ),
        FaqItem(
          questionEn: 'Can I use the blue line like Google Maps navigation?',
          questionTl: 'Maaari ko bang gamitin ang blue line tulad ng Google Maps navigation?',
          answerEn:
              'No. It is only a travel and orientation guide. It does not provide turn-by-turn driving instructions.',
          answerTl:
              'Hindi. Ito ay gabay lamang para sa paglalakbay at oryentasyon. Hindi ito nagbibigay ng turn-by-turn driving instructions.',
        ),
      ],
    ),

    // 3. GPS & COMPASS
    FaqCategory(
      titleEn: 'GPS & Compass',
      titleTl: 'GPS at Compass',
      icon: Icons.explore_outlined,
      items: [
        FaqItem(
          questionEn: 'Why do I need to get closer to the site?',
          questionTl: 'Bakit kailangan kong lumapit pa sa site?',
          answerEn:
              'The app needs to verify that you are physically near the inspection site before you can continue.',
          answerTl:
              'Kailangang matiyak ng app na ikaw ay aktwal na malapit sa inspection site bago ka makapagpatuloy.',
        ),
        FaqItem(
          questionEn: 'How close do I need to be?',
          questionTl: 'Gaano ako dapat kalapit sa site?',
          answerEn:
              'You need to be within 30 meters of the target site.',
          answerTl:
              'Kailangan mong pumuwesto sa loob ng 30 meters mula sa target site.',
        ),
        FaqItem(
          questionEn: 'Why does the button say "Approach site (< 30 m)"?',
          questionTl: 'Bakit sinasabi ng button na "Approach site (< 30 m)"?',
          answerEn:
              'You are still more than 30 meters from the inspection site. Move closer to the site and wait for your GPS reading to update. Once you are within 30 meters, the button will turn blue and allow you to verify your location.',
          answerTl:
              'Lampas ka pa sa 30 meters mula sa inspection site. Lumapit pa sa site at hintaying mag-update ang GPS reading sa iyong screen. Kapag nasa loob ka na ng 30 meters, magiging kulay blue ang button upang ma-verify ang iyong lokasyon.',
        ),
        FaqItem(
          questionEn: 'What is the compass for?',
          questionTl: 'Para saan ang compass?',
          answerEn:
              'The compass helps you determine which direction the target site is located from your current position.',
          answerTl:
              'Tumutulong ang compass upang malaman mo kung saang direksyon naroroon ang target site mula sa iyong kasalukuyang kinatatayuan.',
        ),
      ],
    ),
    // 4. PHOTOS
    FaqCategory(
      titleEn: 'Photos',
      titleTl: 'Mga Litrato',
      icon: Icons.camera_alt_outlined,
      items: [
        FaqItem(
          questionEn: 'Why do I need to take photos?',
          questionTl: 'Bakit kailangang kumuha ng litrato?',
          answerEn:
              'Photos provide visual evidence of the actual site condition during the inspection.',
          answerTl:
              'Ang mga litrato ay nagbibigay ng visual evidence ng totoong kondisyon ng site habang isinasagawa ang inspection.',
        ),
        FaqItem(
          questionEn: 'How many photos can I take per inspection?',
          questionTl:
              'Ilang litrato ang maaari kong kunin sa bawat inspection?',
          answerEn:
              'You can capture and attach up to 10 photos for each inspection.',
          answerTl:
              'Maaari kang kumuha at maglakip ng hanggang 10 litrato para sa bawat inspection.',
        ),
        FaqItem(
          questionEn: 'What happens when I press Save after taking a photo?',
          questionTl: 'Ano ang mangyayari kapag pinindot ang Save matapos kumuha ng litrato?',
          answerEn:
              'The photo is saved as part of your inspection work. You can see it again in the inspection flow and Task Overview.',
          answerTl:
              'Ang litrato ay nase-save bilang bahagi ng iyong inspection record. Makikita mo ito muli sa inspection flow at sa Task Overview.',
        ),
        FaqItem(
          questionEn: 'Why does the photo have location and time information?',
          questionTl: 'Bakit may nakalagay na impormasyon ng lokasyon at oras sa litrato?',
          answerEn:
              'The app places important inspection information such as date, time, and GPS coordinates directly on the photo to help document where and when the photo was taken.',
          answerTl:
              'Inilalagay ng app ang mahahalagang impormasyon tulad ng petsa, oras, at GPS coordinates nang direkta sa litrato upang maidokumento kung saan at kailan ito kinuha.',
        ),
        FaqItem(
          questionEn: 'Can I delete a photo before submitting?',
          questionTl: 'Maaari ko bang burahin ang litrato bago mag-submit?',
          answerEn:
              'Yes. You can remove a photo while the inspection is still being worked on.',
          answerTl:
              'Oo. Maaari mong burahin ang isang litrato habang ginagawa pa ang inspection at bago ito pinal na isumite.',
        ),
      ],
    ),

    // 5. CHECKLIST & FINDINGS
    FaqCategory(
      titleEn: 'Checklist & Findings',
      titleTl: 'Checklist at Findings',
      icon: Icons.fact_check_outlined,
      items: [
        FaqItem(
          questionEn: 'What is Step 4 for?',
          questionTl: 'Para saan ang Step 4?',
          answerEn:
              'Step 4 is the zoning checklist. It helps you check the required inspection conditions in an organized way.',
          answerTl:
              'Ang Step 4 ay ang zoning checklist. Tumutulong ito upang masuri ang mga kinakailangang kondisyon sa maayos at organisadong paraan.',
        ),
        FaqItem(
          questionEn: 'What does 3/5 or 5/5 mean?',
          questionTl: 'Ano ang ibig sabihin ng 3/5 o 5/5?',
          answerEn:
              'It shows how many checklist items you have completed out of the total number of required items.',
          answerTl:
              'Ipinapakita nito kung ilang checklist items na ang iyong natapos mula sa kabuuang bilang ng mga aytem na kailangan.',
        ),
        FaqItem(
          questionEn: 'Do I need a separate Save button for every checklist item?',
          questionTl: 'Kailangan ko ba ng hiwalay na Save button sa bawat checklist item?',
          answerEn:
              'No. Checklist changes are saved as you work.',
          answerTl:
              'Hindi. Awtomatikong nase-save ang mga pagbabago sa checklist habang naglalagay ka ng check.',
        ),
        FaqItem(
          questionEn: 'What is Step 5 for?',
          questionTl: 'Para saan ang Step 5?',
          answerEn:
              'Step 5 is where you record what you observed at the site.',
          answerTl:
              'Ang Step 5 ay kung saan mo itatala ang lahat ng iyong naobserbahan sa mismong site.',
        ),
        FaqItem(
          questionEn: 'What is the difference between Observations and Discrepancy?',
          questionTl: 'Ano ang pagkakaiba ng Observations at Discrepancy?',
          answerEn:
              'Observations describe what you saw at the site.\n\nA Discrepancy records a specific issue or difference that needs attention.',
          answerTl:
              'Ang Observations ay naglalarawan ng pangkalahatang nakita mo sa site.\n\nAng Discrepancy ay nagtatala ng partikular na problema o pagkakaiba sa dapat na gamit ng lupa na nangangailangan ng pansin.',
        ),
        FaqItem(
          questionEn: 'What are Issue Title and Details?',
          questionTl: 'Ano ang Issue Title at Details?',
          answerEn:
              'Issue Title gives the short name of the problem.\n\nDetails explain the problem more clearly.',
          answerTl:
              'Ang Issue Title ang maikling pangalan o pamagat ng problema.\n\nAng Details ang nagpapaliwanag nang mas malinaw tungkol sa nasabing problema.',
        ),
        FaqItem(
          questionEn: 'What is Recommendation?',
          questionTl: 'Ano ang Recommendation?',
          answerEn:
              'Recommendation records the suggested action based on your findings.',
          answerTl:
              'Ang Recommendation ay nagtatala ng iminumungkahing aksyon o susunod na hakbang batay sa iyong mga nakita sa site.',
        ),
      ],
    ),
    // 6. OFFLINE WORK
    FaqCategory(
      titleEn: 'Offline Work',
      titleTl: 'Paggawa nang Offline',
      icon: Icons.wifi_off_outlined,
      items: [
        FaqItem(
          questionEn: 'What happens if I lose internet while inspecting a site?',
          questionTl: 'Ano ang mangyayari kung mawalan ng internet habang nag-iinspeksyon?',
          answerEn:
              'You can continue the supported inspection work. The app saves your work on the device first and waits for an internet connection before sending it to the cloud.',
          answerTl:
              'Maaari kang magpatuloy sa iyong inspection work. Iniimbak muna ng app ang iyong mga ginawa sa mismong device at maghihintay ng internet connection bago ito ipadala sa cloud.',
        ),
        FaqItem(
          questionEn: 'Will my work disappear if I close the app while offline?',
          questionTl: 'Mawawala ba ang aking ginawa kapag isinara ko ang app nang offline?',
          answerEn:
              'Saved inspection work is designed to remain on the device and can be loaded again when you reopen the app.',
          answerTl:
              'Hindi mawawala ang iyong ginawa. Ang na-save na inspection work ay nananatili sa device at muling mabubuksan kapag binuksan mo ulit ang app.',
        ),
        FaqItem(
          questionEn: 'What happens when internet comes back?',
          questionTl: 'Ano ang mangyayari kapag nagkaroon muli ng internet?',
          answerEn:
              'The app detects the connection and starts synchronizing saved work that is waiting to be uploaded.',
          answerTl:
              'Kusa itong madidiskubre ng app at sisimulan ang pag-synchronize ng mga naka-save na gawaing naghihintay mai-upload.',
        ),
      ],
    ),

    // 7. SYNC CENTER
    FaqCategory(
      titleEn: 'Sync Center',
      titleTl: 'Sync Center',
      icon: Icons.sync_outlined,
      items: [
        FaqItem(
          questionEn: 'What is Sync Center?',
          questionTl: 'Ano ang Sync Center?',
          answerEn:
              'Sync Center helps you see and manage inspection information that is waiting to synchronize with the MPDO server.',
          answerTl:
              'Ang Sync Center ay tumutulong upang makita at mapamahalaan ang mga inspection data na naghihintay ma-synchronize sa MPDO server.',
        ),
        FaqItem(
          questionEn: 'Do I need to open Sync Center every time I want to upload my work?',
          questionTl: 'Kailangan ko bang buksan ang Sync Center sa bawat pag-upload ng aking gawa?',
          answerEn:
              'No. Synchronization normally starts automatically when an internet connection becomes available.',
          answerTl:
              'Hindi kailangan. Karaniwang awtomatikong nagsisimula ang synchronization kapag nagkaroon muli ng internet connection.',
        ),
        FaqItem(
          questionEn: 'Then why is there a Sync Now button?',
          questionTl: 'Bakit mayroong Sync Now button kung awtomatiko ito?',
          answerEn:
              'Sync Now lets you manually start synchronization when you want to check or push waiting work.',
          answerTl:
              'Ang Sync Now ay nagbibigay-daan upang manu-manong simulan ang synchronization kung nais mong i-upload o suriin agad ang mga naghihintay na datos.',
        ),
        FaqItem(
          questionEn: 'What do the pending numbers mean?',
          questionTl: 'Ano ang ibig sabihin ng mga numerong nakalagay sa pending?',
          answerEn:
              'They show work that is still waiting to synchronize, such as inspection updates, checklist changes, GPS information, or photos.',
          answerTl:
              'Ipinapakita ng mga ito ang dami ng gawaing naghihintay pang ma-synchronize, tulad ng mga update sa inspection, pagbabago sa checklist, GPS verification, o mga litrato.',
        ),
        FaqItem(
          questionEn: 'What happens if synchronization fails?',
          questionTl: 'Ano ang mangyayari kung hindi magtagumpay ang synchronization?',
          answerEn:
              'The app keeps the item in the synchronization process so it can be retried instead of simply deleting your saved work.',
          answerTl:
              'Pinapanatili ng app ang aytem sa synchronization queue upang masubukang muli sa susunod sa halip na mabura ang iyong na-save na gawa.',
        ),
      ],
    ),
    // 8. INSPECTION FLOW
    FaqCategory(
      titleEn: 'Inspection Flow',
      titleTl: 'Proseso ng Inspection',
      icon: Icons.alt_route_outlined,
      items: [
        FaqItem(
          questionEn: 'Why are there six steps?',
          questionTl: 'Bakit mayroong anim na hakbang (6 Steps)?',
          answerEn:
              'The six steps organize the inspection from checking the site, collecting evidence, recording findings, and reviewing the final result before submission.',
          answerTl:
              'Inaayos ng anim na steps ang buong inspection—mula sa pagpunta sa site, GPS verification, pagkuha ng ebidensya, checklist, pagtatala ng findings, hanggang sa pinal na pagsusuri bago magsumite.',
        ),
        FaqItem(
          questionEn: 'Can I leave an inspection before finishing?',
          questionTl: 'Maaari ba akong lumabas sa inspection bago ito matapos?',
          answerEn:
              'Yes. Saved inspection work can be resumed later.',
          answerTl:
              'Oo. Maaari kang lumabas pansamantala; mase-save ang iyong ginawa at maaari mo itong ipagpatuloy muli.',
        ),
        FaqItem(
          questionEn: 'What are the assessment result options in Step 6?',
          questionTl: 'Ano ang mga pagpipiliang assessment result sa Step 6?',
          answerEn:
              'When finalizing your inspection in Step 6, you choose from four results:\n\n• Compliant: The structure and actual land use match what was declared, with no issues.\n• With Discrepancy: The observed land use differs from what was declared.\n• For Review: Needs supervisor review and sign-off.\n• Requires Reinspection: Site conditions were incomplete or need another visit.',
          answerTl:
              'Sa pagtatapos ng inspection sa Step 6, pipili ka sa apat na resulta:\n\n• Compliant: Tugma ang gusali at aktwal na gamit ng lupa sa idineklara, at walang nakitang problema.\n• With Discrepancy: May pagkakaiba ang naobserbahang gamit ng lupa sa kung ano ang idineklara.\n• For Review: Nangangailangan ng karagdagang pagsusuri at pag-apruba ng supervisor.\n• Requires Reinspection: Hindi kumpleto ang kondisyon sa site o kailangan ng panibagong pagbisita.',
        ),
        FaqItem(
          questionEn: 'What happens after Step 6?',
          questionTl: 'Ano ang mangyayari pagkatapos ng Step 6?',
          answerEn:
              'You review the inspection information and submit the completed inspection. The task then moves to Completed when submission succeeds.',
          answerTl:
              'Susuriin mo ang buong impormasyon ng inspection at isusumite ito. Lilipat ang task sa Completed kapag naging matagumpay ang pagsumite.',
        ),
      ],
    ),

    // 9. REWORK
    FaqCategory(
      titleEn: 'Rework',
      titleTl: 'Rework',
      icon: Icons.replay_rounded,
      items: [
        FaqItem(
          questionEn: 'What is Rework?',
          questionTl: 'Ano ang Rework?',
          answerEn:
              'Rework lets you reopen an already completed inspection so you can correct or update a specific part without starting the entire inspection again.',
          answerTl:
              'Ang Rework ay nagbibigay-daan upang muling buksan ang isang completed na inspection upang ituwid o i-update ang isang partikular na bahagi nang hindi na kailangang simulan muli mula sa simula.',
        ),
        FaqItem(
          questionEn: 'If I open Rework but change nothing, will it become Modified?',
          questionTl: 'Kung bubuksan ko ang Rework ngunit wala akong babaguhin, magiging Modified ba ito?',
          answerEn:
              'No. Simply opening a step for Rework does not mean that the inspection was changed.',
          answerTl:
              'Hindi. Ang pagbukas lamang ng isang step para sa Rework nang walang binabago ay hindi maglalagay ng markang Modified.',
        ),
        FaqItem(
          questionEn: 'When does Modified appear?',
          questionTl: 'Kailan lumalabas ang markang Modified?',
          answerEn:
              'Modified appears when you actually change inspection information during Rework.',
          answerTl:
              'Lumalabas lamang ang markang Modified kapag may aktwal ka nang binago o iniwasto sa impormasyon habang nasa Rework.',
        ),
        FaqItem(
          questionEn: 'Does changing one step erase the other steps?',
          questionTl: 'Mabubura ba ang ibang steps kapag binago ko ang isang step?',
          answerEn:
              'No. Reworking one step does not intentionally erase the information from the other inspection steps.',
          answerTl:
              'Hindi. Ang pagbabago sa isang step sa Rework ay hindi nagbubura sa mga naunang impormasyon at litrato sa iba pang mga step.',
        ),
      ],
    ),
    // 10. REPORTS & SUPPORT — two report types, plus history/status.
    FaqCategory(
      titleEn: 'Reports & Support',
      titleTl: 'Reports & Support',
      icon: Icons.flag_outlined,
      items: [
        FaqItem(
          questionEn: 'What is Reports & Support?',
          questionTl: 'Ano ang Reports & Support?',
          answerEn:
              'Open Profile → Reports & Support to tell the MPDO team what needs attention. '
              'There are two report types: Technical Issue for FieldSync problems, and Application Support '
              'for concerns about a task or application assigned to you.\n\n'
              'My Reports is your history and status list, not another report type.',
          answerTl:
              'Buksan ang Profile → Reports & Support para ipaalam sa MPDO team ang kailangang asikasuhin. '
              'May dalawang uri ng report: Technical Issue para sa problema sa FieldSync, at Application Support '
              'para sa concern sa task o application na nakatalaga sa iyo.\n\n'
              'Ang My Reports ay listahan ng history at status, hindi isa pang uri ng report.',
        ),
        FaqItem(
          questionEn: 'When should I file a Technical Issue?',
          questionTl: 'Kailan ako dapat mag-file ng Technical Issue?',
          answerEn:
              'Use Technical Issue when something is wrong with FieldSync itself: a screen does not respond, '
              'GPS behaves unexpectedly, sync fails, a button does not work, or a map, route or app error appears.\n\n'
              'No task or application is required. Choose the affected screen and describe what happened. '
              'The report first goes to the MPDO team (Admin) for review; it does not directly contact a Planning Officer.',
          answerTl:
              'Gamitin ang Technical Issue kapag may problema sa FieldSync mismo: hindi tumutugon ang screen, '
              'kakaiba ang GPS, hindi gumagana ang sync o button, o may error sa mapa, ruta o app.\n\n'
              'Hindi kailangan ng task o application. Piliin ang apektadong screen at ilarawan ang nangyari. '
              'Sa MPDO team (Admin) muna mapupunta ang report para suriin; hindi ito direktang kumokontak sa Planning Officer.',
        ),
        FaqItem(
          questionEn: 'When should I use Application Support?',
          questionTl: 'Kailan ko gagamitin ang Application Support?',
          answerEn:
              'Use Application Support for incorrect or missing information, additional site information, '
              'clarification, a correction request, or another concern about an exact task or application.\n\n'
              'Select the exact task from your available assignments or completed tasks. You do not choose a Planning Officer. '
              'iMAPS identifies the current Planning Officer and handles routing and follow-up.',
          answerTl:
              'Gamitin ang Application Support para sa mali o kulang na impormasyon, dagdag na impormasyon sa site, '
              'paglilinaw, kahilingan sa pagwawasto, o ibang concern sa isang tiyak na task o application.\n\n'
              'Piliin ang mismong task mula sa mga available mong assignment o completed task. Hindi ikaw ang pipili ng Planning Officer. '
              'Tinutukoy ng iMAPS ang kasalukuyang Planning Officer at inaasikaso ang routing at follow-up.',
        ),
        FaqItem(
          questionEn: 'Why can’t I select my task for Application Support?',
          questionTl: 'Bakit hindi ko mapili ang task ko sa Application Support?',
          answerEn:
              'A task saved by an older version of FieldSync may be missing information needed to link your report correctly. '
              'Open or refresh My Tasks while online, then refresh the tasks in Application Support. '
              'While offline, only tasks already saved on this device are available.',
          answerTl:
              'Maaaring kulang ang impormasyong na-save ng lumang bersyon ng FieldSync upang maitugma nang tama ang report sa task. '
              'Buksan o i-refresh ang My Tasks habang online, saka i-refresh ang mga task sa Application Support. '
              'Kapag offline, ang mga task na naka-save na sa device lamang ang available.',
        ),
        FaqItem(
          questionEn: 'What do the statuses in My Reports mean?',
          questionTl: 'Ano ang ibig sabihin ng mga status sa My Reports?',
          answerEn:
              'My Reports shows both filed reports and reports still waiting on this device.\n\n'
              '• Pending on this device: saved here, not yet confirmed by the server.\n'
              '• Filed / Submitted: the server confirmed receipt; a report reference is available.\n'
              '• Retry needed: saved here after a temporary sending problem; another attempt may work.\n'
              '• Could not be filed: the report was refused. Contact the MPDO team; FieldSync will not keep resending it automatically.\n'
              '• Submission status uncertain: the report may have arrived. Check the filed list before trying again.',
          answerTl:
              'Makikita sa My Reports ang mga na-file na report at ang mga naghihintay pa sa device.\n\n'
              '• Pending on this device: naka-save dito, pero hindi pa nakukumpirma ng server.\n'
              '• Filed / Submitted: nakumpirma ng server ang pagtanggap; may report reference na.\n'
              '• Retry needed: naka-save matapos ang pansamantalang problema sa pagpapadala; maaaring gumana ang susunod na pagtatangka.\n'
              '• Could not be filed: tinanggihan ang report. Kontakin ang MPDO team; hindi ito paulit-ulit na awtomatikong ipapadala ng FieldSync.\n'
              '• Submission status uncertain: maaaring dumating na ang report. Tingnan muna ang filed list bago subukang muli.',
        ),
        FaqItem(
          questionEn: 'Can I file a report while offline?',
          questionTl: 'Maaari ba akong mag-file ng report habang offline?',
          answerEn:
              'Yes. When you tap Submit report, FieldSync saves a valid report on this device before attempting to send it. '
              'If offline, it stays here. When connectivity returns, eligible pending reports can be sent.\n\n'
              'Check My Reports for the delivery status. Text you have only typed into a form is not yet a saved report.',
          answerTl:
              'Oo. Kapag pinindot mo ang Submit report, sine-save muna ng FieldSync ang valid na report sa device bago subukang ipadala. '
              'Kapag offline, mananatili ito rito. Kapag bumalik ang koneksyon, maaaring maipadala ang mga pending report na puwede nang subukan.\n\n'
              'Tingnan sa My Reports ang delivery status. Ang text na na-type mo pa lang sa form ay hindi pa naka-save na report.',
        ),
        FaqItem(
          questionEn: 'What should I do if submission status is uncertain?',
          questionTl: 'Ano ang gagawin ko kung uncertain ang submission status?',
          answerEn:
              'FieldSync cannot tell whether the report reached the server, so it will not silently resend it. '
              'Check My Reports first. If you decide to try sending again, read the confirmation carefully: '
              'resending may create a duplicate.',
          answerTl:
              'Hindi matukoy ng FieldSync kung nakarating ang report sa server, kaya hindi ito basta ipapadala muli. '
              'Tingnan muna ang My Reports. Kung susubukan mong ipadala muli, basahing mabuti ang confirmation: '
              'maaaring makagawa ng duplicate ang muling pagpapadala.',
        ),
        FaqItem(
          questionEn: 'What happens after I file a report?',
          questionTl: 'Ano ang mangyayari pagkatapos kong mag-file ng report?',
          answerEn:
              'For a Technical Issue, the MPDO team (Admin) reviews the FieldSync problem. '
              'For Application Support, iMAPS handles the concern through the current application workflow and Planning Officer.\n\n'
              'Open My Reports to check the status and any review details added by the MPDO team.',
          answerTl:
              'Para sa Technical Issue, sinusuri ng MPDO team (Admin) ang problema sa FieldSync. '
              'Para sa Application Support, inaasikaso ng iMAPS ang concern ayon sa kasalukuyang application workflow at Planning Officer.\n\n'
              'Buksan ang My Reports para makita ang status at anumang detalye ng review mula sa MPDO team.',
        ),
      ],
    ),
  ];
}
