"""Create Testlauf 03 from authored lexical specifications using the 4a/4b split."""
import json
from pathlib import Path

DATE='2026-11-04'
MODEL='GPT-6 (Codex)'

def sense(short, translation, definition_de, definition_en, examples, *, alternatives=None, article=None, plural=None, memory_de=None, memory_en=None, confusion_de=None, confusion_en=None, code=None):
    return {'short':short,'translation':translation,'alternatives':alternatives or [],'de':definition_de,'en':definition_en,'examples':examples,'artikel':article,'plural':plural,'memory_de':memory_de,'memory_en':memory_en,'confusion_de':confusion_de,'confusion_en':confusion_en,'code':code}

def lemma(lang, text, pos, level, senses, *, article=None, plural=None):
    return {'sprache':lang,'text':text,'wortart':pos,'niveau':level,'artikel':article,'plural':plural,'senses':senses}

DE=[
lemma('de','Band','nomen','B1',[
 sense('Buchband','volume','Ein einzelner Teil einer Buchreihe oder eines mehrbändigen Werkes.','One part of a book series or a multi-volume work.', [('Der zweite Band erscheint im Herbst.','The second volume comes out in autumn.'),('Ich lese den ersten Band noch einmal.','I am reading the first volume again.')], article='der',plural='Bände',memory_de='Der Band eines Buches ist ein einzelner Teil einer Reihe.',memory_en='A book volume is one part of a series.',code='de-band-1'),
 sense('Stoff- oder Materialstreifen','ribbon','Ein schmales, langes Stück Stoff oder Material, oft zum Binden.','A long, narrow piece of fabric or other material, often used for tying.', [('Sie band ein rotes Band um das Geschenk.','She tied a red ribbon around the gift.'),('Das Band hält die Vorhänge zusammen.','The ribbon holds the curtains together.')], article='das',plural='Bänder',memory_de='Ein Band aus Stoff kann etwas zusammenhalten oder schmücken.',memory_en='A fabric ribbon can tie or decorate something.',code='de-band-2'),
 sense('Musikgruppe','band','Eine Gruppe von Musikern, die gemeinsam Musik spielt.','A group of musicians who perform music together.', [('Die Band spielt heute Abend im Park.','The band is playing in the park tonight.'),('Unsere Band probt jeden Dienstag.','Our band rehearses every Tuesday.')], article='die',plural='Bands',memory_de='Der Buchband, das Stoffband, die Musikband: Der Artikel hilft beim Unterscheiden.',memory_en='In German, the article changes: der Band, das Band, die Band.',confusion_de='Nicht verwechseln: der Band ist ein Buchteil; die Band ist eine Musikgruppe.',confusion_en='In German, der Band is a book volume; die Band is a music group.',code='de-band-3'),
]),
lemma('de','Leiter','nomen','B1',[
 sense('Gerät zum Hinaufsteigen','ladder','Ein Gerät mit zwei Holmen und Sprossen, auf das man steigt.','A frame with steps that people climb to reach a higher place.', [('Die Leiter steht neben dem Apfelbaum.','The ladder is beside the apple tree.'),('Er stieg vorsichtig auf die Leiter.','He climbed the ladder carefully.')], article='die',plural='Leitern',memory_de='Eine Leiter hat Sprossen, auf denen man steht.',memory_en='A ladder has rungs that you step on.',code='de-leiter-1'),
 sense('Person mit Führungsaufgabe','leader','Eine Person, die für eine Gruppe oder ein Team verantwortlich ist.','A person responsible for guiding or directing a group.', [('Der Leiter erklärt den neuen Plan.','The leader explains the new plan.'),('Der Leiter sprach mit allen Mitarbeitenden.','The leader spoke with all the staff.')], article='der',plural='Leiter',memory_de='Ein Leiter führt Menschen; eine Leiter hat Sprossen.',memory_en='A leader guides people; a ladder has rungs.',confusion_de='Der Leiter ist eine Person; die Leiter ist das Gerät mit Sprossen.',confusion_en='In German, der Leiter is a person; die Leiter is the climbing frame.',code='de-leiter-2'),
]),
lemma('de','See','nomen','B1',[
 sense('Binnengewässer','lake','Ein großes Gewässer, das vollständig von Land umgeben ist.','A large body of water that is completely surrounded by land.', [('Der See friert in kalten Wintern zu.','The lake freezes over in cold winters.'),('Wir schwammen gestern im See.','We swam in the lake yesterday.')], article='der',plural='Seen',memory_de='Der See liegt im Land; die See ist das Meer.',memory_en='In German, der See is a lake; die See is the sea.',confusion_de='Nicht verwechseln: der See ist ein Binnengewässer, die See das Meer.',confusion_en='The German article changes the meaning: der See is a lake, die See is the sea.',code='de-see-1'),
 sense('Meer','sea','Das große, salzige Gewässer zwischen Ländern und Kontinenten.','A large area of salty water between countries and continents.', [('Die See ist heute sehr ruhig.','The sea is very calm today.'),('Bei schwerer See blieb das Boot im Hafen.','In rough seas, the boat stayed in the harbor.')], article='die',memory_de='Die See bedeutet Meer; im üblichen Sinn hat das Wort keinen Plural.',memory_en='Die See means the sea and normally has no plural in this sense.',confusion_de='Der See ist ein Binnengewässer; die See bedeutet Meer.',confusion_en='Der See is an inland lake; die See means the sea.',code='de-see-2'),
]),
lemma('de','Kiefer','nomen','B1',[
 sense('Knochen im Mund','jaw','Der Knochen im Mund, in dem die unteren und oberen Zähne sitzen.','The bone in the mouth that holds the upper or lower teeth.', [('Der Zahnarzt untersuchte ihren Kiefer.','The dentist examined her jaw.'),('Nach dem Sturz tat ihm der Kiefer weh.','His jaw hurt after the fall.')], article='der',plural='Kiefer',memory_de='Der Kieferknochen sitzt im Gesicht; die Kiefer ist auch ein Nadelbaum.',memory_en='Der Kiefer is the jawbone; die Kiefer is also a pine tree.',confusion_de='Der Kiefer ist der Knochen; die Kiefer ist der Baum.',confusion_en='Der Kiefer is the jaw; die Kiefer is the tree.',code='de-kiefer-1'),
 sense('Nadelbaum','pine tree','Ein Nadelbaum mit langen Nadeln und harten Zapfen.','A coniferous tree with long needles and hard cones.', [('Eine Kiefer wächst neben dem alten Haus.','A pine tree grows beside the old house.'),('Im Wald stehen viele hohe Kiefern.','Many tall pine trees stand in the forest.')], article='die',plural='Kiefern',memory_de='Die Kiefer als Baum wächst im Wald; der Kieferknochen sitzt im Gesicht.',memory_en='Die Kiefer is the tree; der Kiefer is the jawbone.',confusion_de='Die Kiefer ist ein Baum; der Kiefer ist der Knochen im Gesicht.',confusion_en='Die Kiefer is a tree; der Kiefer is the jawbone.',code='de-kiefer-2'),
]),
lemma('de','Mutter','nomen','B1',[
 sense('weiblicher Elternteil','mother','Eine Frau, die ein Kind geboren hat oder großzieht.','A woman who has given birth to or raises a child.', [('Meine Mutter holt mich nach der Schule ab.','My mother is picking me up after school.'),('Die Mutter wartet vor dem Klassenraum.','The mother is waiting outside the classroom.')], article='die',plural='Mütter',memory_de='Mütter gehören zur Familie; Muttern passen auf Schrauben.',memory_en='German uses Mütter for mothers and Muttern for screw nuts.',confusion_de='Die Mutter als Elternteil hat den Plural Mütter; das Schraubenteil heißt Muttern.',confusion_en='The family word has plural Mütter; the threaded part has plural Muttern.',code='de-mutter-1'),
 sense('Schraubenteil','nut','Ein Metallteil mit Innengewinde, das auf eine Schraube gedreht wird.','A small metal part with internal threads that screws onto a bolt.', [('Dreh die Mutter auf die Schraube.','Turn the nut onto the bolt.'),('Die Mutter hält das Rad an der Achse fest.','The nut holds the wheel on the axle.')], article='die',plural='Muttern',memory_de='Mütter gehören zur Familie; Muttern passen auf Schrauben.',memory_en='German uses Mütter for mothers and Muttern for screw nuts.',confusion_de='Die Mutter als Elternteil hat den Plural Mütter; das Schraubenteil heißt Muttern.',confusion_en='The family word has plural Mütter; the threaded part has plural Muttern.',code='de-mutter-2'),
]),
lemma('de','werfen','verb','B1',[
 sense('etwas durch die Luft bewegen','throw','Etwas mit der Hand durch die Luft bewegen.','To send something through the air with your hand.', [('Sie wirft den Ball zurück.','She throws the ball back.'),('Er hat den Schlüssel auf den Tisch geworfen.','He threw the key onto the table.')], code='de-werfen-1'),
]),
lemma('de','schlafen','verb','A2',[
 sense('ruhen im Schlaf','sleep','Im Schlaf ruhen, nicht wach sein.','To rest while asleep.', [('Das Baby schläft schon.','The baby is already asleep.'),('Wir schliefen im Zug ein.','We fell asleep on the train.')], code='de-schlafen-1'),
]),
lemma('de','geben','verb','A2',[
 sense('jemandem etwas reichen','give','Jemandem etwas überreichen oder zur Verfügung stellen.','To hand something to someone.', [('Sie gibt dem Kind ein Glas Wasser.','She gives the child a glass of water.'),('Er gab mir gestern seinen Schlüssel.','He gave me his key yesterday.')], code='de-geben-1'),
]),
lemma('de','behalten','verb','B1',[
 sense('nicht zurückgeben','keep','Etwas weiter bei sich haben und nicht zurückgeben.','To continue to have something.', [('Du kannst das Buch behalten.','You can keep the book.'),('Sie behielt den Brief als Erinnerung.','She kept the letter as a memory.')], code='de-behalten-1'),
]),
lemma('de','ziehen','verb','B1',[
 sense('mit Kraft bewegen','pull','Etwas mit Kraft zu sich oder an einen anderen Ort bewegen.','To use force to move something toward you or to another place.', [('Er zieht den Koffer über den Boden.','He pulls the suitcase across the floor.'),('Sie zog den Vorhang zu.','She pulled the curtain closed.')], memory_de='Hier bedeutet ziehen, etwas mit Kraft zu bewegen.',memory_en='Here, ziehen means to pull something.',code='de-ziehen-1'),
 sense('den Wohnort wechseln','move','Seinen Wohnort wechseln und in eine andere Wohnung oder ein anderes Haus gehen.','To leave one home and begin living in another place.', [('Wir ziehen im Mai nach Hamburg.','We are moving to Hamburg in May.'),('Sie ist letztes Jahr nach Berlin gezogen.','She moved to Berlin last year.')], memory_de='Wenn man den Wohnort wechselt, zieht man um.',memory_en='When changing homes, German uses ziehen or umziehen.',code='de-ziehen-2'),
]),
lemma('de','erwerben','verb','B2',[
 sense('durch Kauf oder Leistung bekommen','acquire','Etwas durch Kauf, Arbeit oder Lernen bekommen.','To get or gain something through purchase, effort, or learning.', [('Sie erwarb ein altes Haus am Stadtrand.','She acquired an old house outside the city.'),('Das Unternehmen hat die Rechte erworben.','The company acquired the rights.')], alternatives=['acquire','obtain'], code='de-erwerben-1'),
]),
lemma('de','öffentlich','adjektiv','B1',[
 sense('für alle zugänglich','public','Für alle Menschen zugänglich oder für alle bestimmt.','Open or available for everyone to use or attend.', [('Die Sitzung ist öffentlich.','The meeting is open to the public.'),('Der Park ist öffentlich zugänglich.','The park is open to the public.')], code='de-oeffentlich-1'),
]),
lemma('de','seltsam','adjektiv','B1',[
 sense('ungewöhnlich und schwer erklärbar','strange','Ungewöhnlich und deshalb überraschend oder schwer zu erklären.','Unusual in a way that is surprising or difficult to explain.', [('Die Antwort klingt seltsam.','The answer sounds strange.'),('Es war ein seltsamer Zufall.','It was a strange coincidence.')], code='de-seltsam-1'),
]),
lemma('de','dünn','adjektiv','A2',[
 sense('geringe Dicke','thin','Von einer Seite zur anderen nur wenig dick.','Having little distance from one side to the other.', [('Das Papier ist sehr dünn.','The paper is very thin.'),('Die dünne Suppe schmeckt nicht gut.','The thin soup does not taste good.')], code='de-duenn-1'),
]),
lemma('de','sauer','adjektiv','A2',[
 sense('säuerlicher Geschmack','sour','Mit einem starken Geschmack wie bei einer Zitrone oder Essig.','Having a sharp taste like lemon or vinegar.', [('Die Zitrone schmeckt sauer.','The lemon tastes sour.'),('Die Beeren waren noch sauer.','The berries were still sour.')], code='de-sauer-1'),
]),
lemma('de','oft','adverb','A2',[
 sense('häufig','often','Viele Male oder in kurzen Abständen.','Many times or at short intervals.', [('Sie fährt oft mit dem Rad zur Arbeit.','She often cycles to work.'),('Wir treffen uns oft nach dem Unterricht.','We often meet after class.')], code='de-oft-1'),
]),
lemma('de','kaum','adverb','B1',[
 sense('fast nicht','barely','Nur in sehr kleinem Maß oder fast gar nicht.','Only to a very small degree or almost not at all.', [('Ich konnte die Musik kaum hören.','I could barely hear the music.'),('Wegen des Nebels sahen wir kaum etwas.','Because of the fog, we could barely see anything.')], code='de-kaum-1'),
]),
lemma('de','während','praeposition','B1',[
 sense('zur selben Zeit wie','during','In der Zeit, in der etwas anderes geschieht.','Throughout the time when another event is happening.', [('Während des Gesprächs blieb es ruhig.','It stayed quiet during the conversation.'),('Während der Reise las sie ein Buch.','She read a book during the journey.')], code='de-waehrend-1'),
]),
lemma('de','gegen','praeposition','A2',[
 sense('Kontakt mit einer Fläche','against','In Kontakt mit einer Fläche oder mit Bewegung auf sie zu.','Touching a surface or moving toward it.', [('Der Regen schlug gegen das Fenster.','The rain beat against the window.'),('Die Leiter lehnte gegen die Wand.','The ladder rested against the wall.')], code='de-gegen-1'),
 sense('Widerstand oder Gegnerschaft','against','Im Widerstand zu jemandem oder als Gegner in einem Wettkampf.','Opposing someone or competing with them.', [('Unsere Mannschaft spielt gegen den Tabellenführer.','Our team is playing against the league leaders.'),('Sie stimmte gegen den Vorschlag.','She voted against the proposal.')], code='de-gegen-2'),
]),
lemma('de','ohne','praeposition','A1',[
 sense('nicht mit etwas','without','Wenn etwas oder jemand nicht dabei ist.','When something is not there or not used.', [('Er ging ohne Jacke hinaus.','He went outside without a coat.'),('Sie trinkt ihren Tee ohne Zucker.','She drinks her tea without sugar.')], code='de-ohne-1'),
]),
]

EN=[
lemma('en','bark','nomen','B1',[
 sense('sound made by a dog','Bellen','Ein kurzes, lautes Geräusch, das ein Hund macht.','The short, loud sound that a dog makes.', [('We heard a loud bark outside.','Wir hörten draußen ein lautes Bellen.'),('The dog’s bark woke the baby.','Das Bellen des Hundes weckte das Baby.')],memory_de='Bark kann das Bellen eines Hundes oder die Rinde eines Baumes bedeuten.',memory_en='Bark can mean a dog’s sound or the outer covering of a tree.',code='en-bark-1'),
 sense('outer covering of a tree','Baumrinde','Die raue äußere Schicht, die den Stamm eines Baumes schützt.','The rough outer layer that covers and protects a tree trunk.', [('The bark protects the tree.','Die Rinde schützt den Baum.'),('A bird sat on the bark of the old tree.','Ein Vogel saß auf der Rinde des alten Baumes.')],memory_de='Bark kann die Rinde eines Baumes oder das Bellen eines Hundes bedeuten.',memory_en='Bark can mean a tree’s outer covering or a dog’s sound.',code='en-bark-2'),
],plural='barks'),
lemma('en','crane','nomen','B1',[
 sense('large wading bird','Kranich','Ein großer Watvogel mit langen Beinen und langem Hals.','A large bird with long legs and a long neck, often found near water.', [('A crane walked through the marsh.','Ein Kranich ging durch den Sumpf.'),('The crane has a long, pointed beak.','Der Kranich hat einen langen, spitzen Schnabel.')],memory_de='A crane kann ein Kranich sein; die Maschine hebt schwere Lasten.',memory_en='A crane can be a bird; the machine lifts heavy loads.',code='en-crane-1'),
 sense('lifting machine','Kran','Eine Maschine, die schwere Dinge hochhebt und bewegt.','A machine used to lift and move heavy objects.', [('The crane lifted a steel beam.','Der Kran hob einen Stahlträger.'),('A crane stood beside the new building.','Ein Kran stand neben dem neuen Gebäude.')],memory_de='Die Maschine crane hebt Lasten; der Vogel crane ist ein Kranich.',memory_en='The machine crane lifts loads; the bird crane is a wading bird.',code='en-crane-2'),
],plural='cranes'),
lemma('en','match','nomen','A2',[
 sense('sports contest','Spiel','Ein sportlicher Wettkampf zwischen zwei Personen oder Teams.','A sports contest between two people or teams.', [('The match ended in a draw.','Das Spiel endete unentschieden.'),('We watched the match on Saturday.','Wir sahen das Spiel am Samstag.')],memory_de='Match bedeutet hier ein Sportspiel; ein anderes match ist ein Streichholz.',memory_en='Match can mean a sports contest or a small stick used to light a fire.',code='en-match-1'),
 sense('small stick for lighting','Streichholz','Ein kleines Holzstäbchen, mit dem man ein Feuer anzünden kann.','A small stick used to start a fire.', [('He lit the fire with a match.','Er entzündete das Feuer mit einem Streichholz.'),('The match burned for a few seconds.','Das Streichholz brannte einige Sekunden.')],memory_de='Ein match zum Anzünden heißt auf Deutsch Streichholz; ein Sport-match ist ein Spiel.',memory_en='A match can be a lighting stick or a sports contest.',code='en-match-2'),
],plural='matches'),
lemma('en','seal','nomen','B2',[
 sense('sea animal','Robbe','Ein Meeressäugetier mit Flossen, das an Küsten lebt.','A sea mammal with flippers that often lives near coasts.', [('A seal rested on a rock near the shore.','Eine Robbe ruhte auf einem Felsen am Ufer.'),('We saw a seal swimming in the bay.','Wir sahen eine Robbe in der Bucht schwimmen.')],memory_de='Seal kann eine Robbe oder ein amtliches Siegel bedeuten.',memory_en='Seal can mean a sea animal or an official mark.',code='en-seal-1'),
 sense('official mark','Siegel','Ein Zeichen auf einem Dokument, das zeigt, dass es echt oder offiziell ist.','A mark on a document showing that it is genuine or official.', [('The envelope bears the official seal.','Der Umschlag trägt das amtliche Siegel.'),('She pressed the seal into the soft wax.','Sie drückte das Siegel in das weiche Wachs.')],memory_de='Das seal auf einem Dokument ist ein Siegel; das Tier ist eine Robbe.',memory_en='A seal on a document is an official mark; the animal is a marine mammal.',code='en-seal-2'),
],plural='seals'),
lemma('en','band','nomen','B1',[
 sense('group of musicians','Band','Eine Gruppe von Musikern, die gemeinsam Musik spielt.','A group of musicians who perform music together.', [('The band played at the festival.','Die Band spielte auf dem Festival.'),('A local band released a new song.','Eine lokale Band veröffentlichte ein neues Lied.')],memory_de='Band kann eine Musikgruppe oder ein schmales Materialstück sein.',memory_en='Band can mean a music group or a narrow strip of material.',code='en-band-1'),
 sense('narrow strip','Streifen','Ein schmales Stück Material, das etwas umgibt, verbindet oder hält.','A narrow strip of material that wraps, joins, or holds things together.', [('He wore a band around his wrist.','Er trug ein Band um sein Handgelenk.'),('A rubber band holds the papers together.','Ein Gummiband hält die Papiere zusammen.')],alternatives=['Band'],memory_de='Band kann eine Musikgruppe oder ein schmales Materialstück sein.',memory_en='Band can mean a music group or a narrow strip of material.',code='en-band-2'),
],plural='bands'),
lemma('en','throw','verb','A2',[
 sense('send through the air by hand','werfen','Etwas mit der Hand durch die Luft bewegen.','To send something through the air with your hand.', [('She threw the ball back to me.','Sie warf mir den Ball zurück.'),('He has thrown the keys onto the table.','Er hat die Schlüssel auf den Tisch geworfen.')],code='en-throw-1'),
]),
lemma('en','sleep','verb','A1',[
 sense('rest while unconscious','schlafen','Im Schlaf ruhen, nicht wach sein.','To rest while asleep.', [('The baby slept for three hours.','Das Baby schlief drei Stunden.'),('I have slept badly this week.','Ich habe diese Woche schlecht geschlafen.')],code='en-sleep-1'),
]),
lemma('en','give','verb','A1',[
 sense('hand something to someone','geben','Jemandem etwas überreichen oder zur Verfügung stellen.','To hand something to someone.', [('She gave him a glass of water.','Sie gab ihm ein Glas Wasser.'),('They have given us clear instructions.','Sie haben uns klare Anweisungen gegeben.')],code='en-give-1'),
]),
lemma('en','keep','verb','A1',[
 sense('continue to have something','behalten','Etwas weiter bei sich haben.','To continue to have something.', [('You can keep the book.','Du kannst das Buch behalten.'),('She kept the letter as a memory.','Sie behielt den Brief als Erinnerung.')],code='en-keep-1'),
]),
lemma('en','acquire','verb','B2',[
 sense('get or gain something','erwerben','Etwas durch Kauf, Arbeit oder Lernen bekommen.','To get or gain something through purchase, effort, or learning.', [('She acquired an old house outside the city.','Sie erwarb ein altes Haus am Stadtrand.'),('The company acquired the rights.','Das Unternehmen erwarb die Rechte.')],alternatives=['erlangen'],code='en-acquire-1'),
]),
lemma('en','obtain','verb','B2',[
 sense('get something through effort','erhalten','Etwas nach einer Suche, durch Mühe oder bei einer Stelle bekommen.','To get something after effort, searching, or asking an authority.', [('I obtained a permit from the city.','Ich erhielt eine Genehmigung von der Stadt.'),('They obtained permission to enter.','Sie erhielten die Erlaubnis einzutreten.')],alternatives=['bekommen'],code='en-obtain-1'),
]),
lemma('en','public','adjektiv','B1',[
 sense('open or available to everyone','öffentlich','Für alle Menschen zugänglich oder für alle bestimmt.','Open or available for everyone to use or attend.', [('The meeting is open to the public.','Die Sitzung ist öffentlich.'),('Public transport stops here.','Hier hält der öffentliche Nahverkehr.')],code='en-public-1'),
]),
lemma('en','strange','adjektiv','A2',[
 sense('unusual and surprising','seltsam','Ungewöhnlich und deshalb überraschend oder schwer zu erklären.','Unusual in a way that is surprising or difficult to explain.', [('It seems strange to leave so early.','Es scheint seltsam, so früh zu gehen.'),('I heard a strange noise outside.','Ich hörte draußen ein seltsames Geräusch.')],code='en-strange-1'),
]),
lemma('en','thin','adjektiv','A2',[
 sense('small distance between sides','dünn','Von einer Seite zur anderen nur wenig dick.','Having little distance from one side to the other.', [('The paper is thin and easy to tear.','Das Papier ist dünn und leicht zu zerreißen.'),('The ice was too thin to walk on.','Das Eis war zu dünn, um darauf zu gehen.')],code='en-thin-1'),
]),
lemma('en','sour','adjektiv','A2',[
 sense('sharp acidic taste','sauer','Mit einem starken Geschmack wie bei einer Zitrone oder Essig.','Having a sharp taste like lemon or vinegar.', [('The lemon tastes sour.','Die Zitrone schmeckt sauer.'),('The berries were still sour.','Die Beeren waren noch sauer.')],code='en-sour-1'),
]),
lemma('en','often','adverb','A1',[
 sense('many times','oft','Viele Male oder in kurzen Abständen.','Many times or at short intervals.', [('She often cycles to work.','Sie fährt oft mit dem Rad zur Arbeit.'),('We often meet after class.','Wir treffen uns oft nach dem Unterricht.')],code='en-often-1'),
]),
lemma('en','barely','adverb','B1',[
 sense('almost not','kaum','Nur in sehr kleinem Maß oder fast gar nicht.','Only to a very small degree or almost not at all.', [('I could barely hear the music.','Ich konnte die Musik kaum hören.'),('Because of the fog, we could barely see anything.','Wegen des Nebels sahen wir kaum etwas.')],code='en-barely-1'),
]),
lemma('en','during','praeposition','B1',[
 sense('throughout a period','während','In der Zeit, in der etwas anderes geschieht.','Throughout the time when another event is happening.', [('She read during the journey.','Sie las während der Reise.'),('The phone rang during dinner.','Das Telefon klingelte während des Abendessens.')],code='en-during-1'),
]),
lemma('en','against','praeposition','A2',[
 sense('contact with a surface','gegen','In Kontakt mit einer Fläche oder mit Bewegung auf sie zu.','Touching a surface or moving toward it.', [('The rain beat against the window.','Der Regen schlug gegen das Fenster.'),('The ladder rested against the wall.','Die Leiter lehnte gegen die Wand.')],code='en-against-1'),
 sense('opposition or competition','gegen','Im Widerstand zu jemandem oder als Gegner in einem Wettkampf.','Opposing someone or competing with them.', [('Our team played against the league leaders.','Unsere Mannschaft spielt gegen den Tabellenführer.'),('She voted against the proposal.','Sie stimmte gegen den Vorschlag.')],code='en-against-2'),
]),
lemma('en','without','praeposition','A1',[
 sense('not having or using something','ohne','Wenn etwas fehlt oder nicht benutzt wird.','When something is not there or not used.', [('He went out without a coat.','Er ging ohne Jacke hinaus.'),('She drinks tea without sugar.','Sie trinkt Tee ohne Zucker.')],code='en-without-1'),
]),
]

# Add symmetric links; Erwerb/acquire/obtain is intentionally one-to-many.
LINKS=[
('de-band-3','en-band-1'),('de-band-2','en-band-2'),
('de-erwerben-1','en-acquire-1'),('de-erwerben-1','en-obtain-1'),
('de-werfen-1','en-throw-1'),('de-schlafen-1','en-sleep-1'),
('de-geben-1','en-give-1'),('de-behalten-1','en-keep-1'),
('de-oeffentlich-1','en-public-1'),('de-seltsam-1','en-strange-1'),
('de-duenn-1','en-thin-1'),('de-sauer-1','en-sour-1'),
('de-oft-1','en-often-1'),('de-kaum-1','en-barely-1'),
('de-waehrend-1','en-during-1'),('de-gegen-1','en-against-1'),('de-gegen-2','en-against-2'),('de-ohne-1','en-without-1')]

entries=[]; inputs=[]; ids_by_code={}
for spec in DE+EN:
    lang=spec['sprache']; text=spec['text']; pos=spec['wortart']; level=spec['niveau']
    slug=text.casefold().replace('ä','ae').replace('ö','oe').replace('ü','ue').replace('ß','ss').replace(' ','-')
    lemma_id=f'{lang}-{slug}-{pos}'
    inputs.append({'sprache':lang,'text':text,'wortart':pos,'niveau':level,'id':lemma_id})
    senses=[]
    for index,sp in enumerate(spec['senses'],1):
        sid=f'{lemma_id}-{index}'
        if sp['code']: ids_by_code[sp['code']]=sid
        target_lang='en' if lang=='de' else 'de'
        translation=sp['translation'] if lang=='de' else sp['translation']
        if lang=='de':
            de_examples=[a for a,b in sp['examples']]
            en_examples=[b for a,b in sp['examples']]
        else:
            en_examples=[a for a,b in sp['examples']]
            de_examples=[b for a,b in sp['examples']]
        explanations=[]
        for explanation_lang in ('de','en'):
            source_sentences=de_examples if lang=='de' else en_examples
            translated_sentences=en_examples if lang=='de' else de_examples
            examples=[{'satz':sent,'uebersetzung':None if explanation_lang==lang else translated_sentences[i],'quelle':'ki','quelle_id':None} for i,sent in enumerate(source_sentences)]
            explanation={'erklaersprache':explanation_lang,'stufe':level,'definition':sp[explanation_lang],'merkhilfe':sp['memory_de' if explanation_lang=='de' else 'memory_en'],'verwechslung':sp['confusion_de' if explanation_lang=='de' else 'confusion_en'],'beispiele':examples,'qualitaet':{'status':'roh','pruef_score':None,'hinweise':[],'modellversion':MODEL,'datum':DATE}}
            explanations.append(explanation)
        sense_obj={'id':sid,'bedeutung_kurz':sp['short'],'uebersetzung':{'sprache':target_lang,'text':translation,'alternativen':sp['alternatives'],'verknuepfte_sense_ids':[]},'explanations':explanations}
        if sp['artikel'] is not None: sense_obj['artikel']=sp['artikel']
        if sp['plural'] is not None: sense_obj['plural']=sp['plural']
        senses.append(sense_obj)
    lemma_obj={'id':lemma_id,'sprache':lang,'text':text,'wortart':pos,'ipa':None,'haeufigkeitsrang':None,'niveau':level,'artikel':spec['artikel'],'plural':spec['plural']}
    entries.append({'lemma':lemma_obj,'senses':senses,'qualitaet':{'status':'roh','pruef_score':None,'hinweise':[],'modellversion':MODEL,'datum':DATE}})

for left_code,right_code in LINKS:
    left=ids_by_code[left_code]; right=ids_by_code[right_code]
    entry_by_sense={s['id']:s for e in entries for s in e['senses']}
    entry_by_sense[left]['uebersetzung']['verknuepfte_sense_ids'].append(right)
    entry_by_sense[right]['uebersetzung']['verknuepfte_sense_ids'].append(left)

Path('tests/testlauf-03-eingabe.json').write_text(json.dumps(inputs,ensure_ascii=False,indent=2)+'\n')
Path('tests/testlauf-03-ergebnisse.json').write_text(json.dumps(entries,ensure_ascii=False,indent=2)+'\n')
# Preserve the Step 4a/4b staging artifacts for review and cost accounting.
by_sense={s['id']:(e['lemma'],s) for e in entries for s in e['senses']}
stage4a=[]; stage4b=[]
for sense_id,(lemma_obj,sense_obj) in by_sense.items():
    learning_lang=lemma_obj['sprache']
    cross_explanation=next(ex for ex in sense_obj['explanations'] if ex['erklaersprache']!=learning_lang)
    stage4a.append({'sense_id':sense_id,'lernsprache':learning_lang,'beispiele':[{'satz':b['satz'],'uebersetzung_andere_sprache':b['uebersetzung'],'quelle':b['quelle'],'quelle_id':b['quelle_id']} for b in cross_explanation['beispiele']]})
    for ex in sense_obj['explanations']:
        stage4b.append({'sense_id':sense_id,'erklaersprache':ex['erklaersprache'],'stufe':ex['stufe'],'definition':ex['definition'],'merkhilfe':ex['merkhilfe'],'verwechslung':ex['verwechslung'],'qualitaet':ex['qualitaet']})
Path('tests/testlauf-03-4a-beispiele.json').write_text(json.dumps(stage4a,ensure_ascii=False,indent=2)+'\n')
Path('tests/testlauf-03-4b-erklaerungen.json').write_text(json.dumps(stage4b,ensure_ascii=False,indent=2)+'\n')
# Emit the example-free skeleton consumed by the local 4a/4b export step.
import copy
basis=copy.deepcopy(entries)
for entry in basis:
    for sense_obj in entry['senses']:
        sense_obj['explanations']=[]
Path('tests/testlauf-03-basis.json').write_text(json.dumps(basis,ensure_ascii=False,indent=2)+'\n')
