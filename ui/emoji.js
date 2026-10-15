// Sélecteur d'emoji du lanceur (« : »). Mots-clés en français et en anglais.
const RAW = `😀|sourire content heureux smile happy grin
😃|sourire joie smiley happy
😄|rire sourire yeux laugh smile
😁|grand sourire dents grin beam
😆|mort de rire mdr laugh
😅|sueur gene ouf sweat
🤣|mdr ptdr rire par terre rofl
😂|larmes de joie mdr lol joy
🙂|sourire leger slight smile
🙃|tete a l'envers ironie upside
😉|clin d'oeil wink
😊|rougir sourire timide blush
😇|ange innocent halo angel
🥰|amoureux coeurs love hearts
😍|yeux coeurs amour heart eyes love
🤩|etoiles waouh star struck
😘|bisou baiser kiss
😗|bisou kiss
😚|bisou yeux fermes kiss
😋|miam delicieux yum
😛|langue tongue
😜|langue clin d'oeil wink tongue crazy
🤪|fou zany crazy
😝|langue yeux plisses squint tongue
🤑|argent riche money
🤗|calin hug
🤭|oups main bouche giggle
🤫|chut silence shush
🤔|reflechir hmm think
🤐|bouche cousue zip
🤨|sourcil sceptique raised eyebrow
😐|neutre neutral
😑|sans expression expressionless
😶|sans bouche muet
😏|narquois smirk
😒|blase unamused
🙄|leve les yeux eye roll
😬|grimace gene grimace
😮‍💨|souffle soupir exhale
🤥|menteur pinocchio lie
😌|soulage apaise relieved
😔|pensif triste pensive
😪|endormi sleepy
🤤|bave drool
😴|dodo sommeil sleep
😷|masque malade mask
🤒|fievre thermometre sick
🤕|blesse bandage hurt
🤢|nausee vert nausea
🤮|vomir vomit
🥵|chaud canicule hot
🥶|froid gele cold
🥴|bourre ivre woozy
😵|etourdi dizzy
🤯|explose mind blown
🤠|cowboy
🥳|fete anniversaire party
🥸|deguise disguise
😎|lunettes cool sunglasses
🤓|intello geek nerd
🧐|monocle curieux
😕|confus confused
😟|inquiet worried
🙁|triste leger frown
😮|bouche ouverte surpris wow
😯|ebahi hushed
😲|stupefait astonished
😳|rougir gene flushed
🥺|supplier yeux pleading
🥹|emu larmes retenues
😦|consterne frowning
😧|angoisse anguished
😨|peur fearful
😰|anxieux sueur anxious
😥|decu soulage sad relieved
😢|pleurer larme cry
😭|sanglot pleure fort sob
😱|cri peur scream
😖|confondu confounded
😣|perseverer persevere
😞|decu disappointed
😓|sueur froide downcast
😩|epuise weary
😫|fatigue tired
🥱|baille ennui yawn
😤|enerve vapeur triumph huff
😡|colere rouge rage angry
😠|fache angry
🤬|insulte jurer cursing
😈|diable sourire devil
👿|diable fache imp
💀|crane mort skull dead
☠️|tete de mort danger
💩|caca poop
🤡|clown
👹|ogre
👻|fantome ghost boo
👽|alien extraterrestre
🤖|robot
😺|chat sourire cat
😹|chat mdr cat joy
😻|chat amoureux cat
🙈|singe yeux cache see no evil
🙉|singe oreilles hear no evil
🙊|singe bouche speak no evil
💋|bisou levres kiss
💌|lettre d'amour love letter
💘|coeur fleche cupid
💝|coeur cadeau gift heart
💖|coeur brillant sparkling heart
💗|coeur grandissant growing heart
💓|coeur battant beating heart
💞|coeurs tournants revolving hearts
💕|deux coeurs two hearts
💔|coeur brise broken heart
❤️‍🔥|coeur en feu heart fire
❤️|coeur rouge amour red heart love
🧡|coeur orange heart
💛|coeur jaune heart
💚|coeur vert heart
💙|coeur bleu heart
💜|coeur violet heart
🤎|coeur marron heart
🖤|coeur noir heart
🤍|coeur blanc heart
💯|cent parfait hundred
💢|colere anger
💥|boum explosion boom
💫|etourdi dizzy star
💦|gouttes sueur splash
💨|vite vent dash
💬|bulle message speech
💭|pensee bulle thought
💤|zzz dodo sleep
👋|salut coucou main wave hello
🤚|main levee raised back
✋|main stop high five
🖖|vulcain spock
👌|ok parfait
🤌|italien pinched
🤏|un peu pinch
✌️|victoire paix peace victory
🤞|croise les doigts chance fingers crossed
🤟|je t'aime love you
🤘|rock metal horns
🤙|appelle moi call me shaka
👈|gauche left
👉|droite right
👆|haut up
👇|bas down
☝️|index haut
👍|pouce ok bien like thumbs up
👎|pouce bas nul dislike thumbs down
✊|poing fist
👊|coup de poing punch
🤛|poing gauche
🤜|poing droit
👏|bravo applaudir clap
🙌|hourra celebration raise hands
👐|mains ouvertes
🤲|paumes
🤝|poignee de main accord handshake deal
🙏|merci priere svp please pray thanks
✍️|ecrire writing
💅|vernis nail
🤳|selfie
💪|muscle fort biceps strong
🧠|cerveau brain
👀|yeux regarder eyes look
👁️|oeil eye
👅|langue tongue
👄|bouche mouth
👶|bebe baby
🧒|enfant child
👦|garcon boy
👧|fille girl
🧑|personne person
👨|homme man
👩|femme woman
🧓|ancien older
👴|grand-pere old man
👵|grand-mere old woman
🙋|lever la main raise hand
🤷|bof je sais pas shrug
🤦|facepalm desespoir
🙇|reverence bow
💁|info
🙅|non no
🙆|ok
🧑‍💻|developpeur informaticien dev coder
🧑‍🎓|etudiant student
🧑‍🍳|cuisinier chef cook
🧑‍🚀|astronaute astronaut
🥷|ninja
🦸|super-heros superhero
🧙|magicien wizard
🧛|vampire
🧟|zombie
🧞|genie
🧜|sirene mermaid
🧚|fee fairy
🎅|pere noel santa
🏃|courir run
🚶|marcher walk
💃|danser danse dance
🕺|danseur dance
👯|fete danse bunny
🧘|yoga zen meditation
🛌|lit dormir bed
👪|famille family
🐶|chien dog
🐱|chat cat
🐭|souris mouse
🐹|hamster
🐰|lapin rabbit bunny
🦊|renard fox
🐻|ours bear
🐼|panda
🐨|koala
🐯|tigre tiger
🦁|lion
🐮|vache cow
🐷|cochon pig
🐸|grenouille frog
🐵|singe monkey
🐔|poule chicken
🐧|pingouin manchot penguin
🐦|oiseau bird
🐤|poussin chick
🦆|canard duck
🦅|aigle eagle
🦉|hibou chouette owl
🦇|chauve-souris bat
🐺|loup wolf
🐗|sanglier boar
🐴|cheval horse
🦄|licorne unicorn
🐝|abeille bee
🐛|chenille bug
🦋|papillon butterfly
🐌|escargot snail
🐞|coccinelle ladybug
🐜|fourmi ant
🕷️|araignee spider
🐢|tortue turtle
🐍|serpent snake
🦖|t-rex dinosaure dinosaur
🐙|pieuvre poulpe octopus
🦑|calamar squid
🦐|crevette shrimp
🦀|crabe crab
🐠|poisson tropical fish
🐟|poisson fish
🐬|dauphin dolphin
🐳|baleine whale
🦈|requin shark
🐊|crocodile
🐘|elephant
🦒|girafe giraffe
🐿️|ecureuil squirrel
🦔|herisson hedgehog
🐾|pattes traces paw
💐|bouquet fleurs
🌸|fleur cerisier sakura blossom
🌹|rose
🌺|hibiscus
🌻|tournesol sunflower
🌷|tulipe tulip
🌱|pousse plante sprout
🌲|sapin arbre tree
🌳|arbre tree
🌴|palmier palm
🌵|cactus
🍀|trefle chance clover luck
🍁|erable feuille automne maple
🍂|feuilles automne fall leaves
🍄|champignon mushroom
🌍|terre monde europe afrique earth world
🌎|terre amerique earth
🌏|terre asie earth
🌙|lune croissant moon
🌕|pleine lune full moon
⭐|etoile star
🌟|etoile brillante glowing star
✨|etincelles paillettes sparkles magie
⚡|eclair electricite zap lightning
🔥|feu flamme fire lit
🌈|arc-en-ciel rainbow
☀️|soleil sun
🌤️|soleil nuage
⛅|nuageux partly cloudy
☁️|nuage cloud
🌧️|pluie rain
⛈️|orage storm
❄️|neige flocon snow
☃️|bonhomme de neige snowman
💧|goutte eau drop water
🌊|vague mer wave
🍏|pomme verte apple
🍎|pomme rouge apple
🍐|poire pear
🍊|orange mandarine
🍋|citron lemon
🍌|banane banana
🍉|pasteque watermelon
🍇|raisin grapes
🍓|fraise strawberry
🍒|cerises cherry
🍑|peche peach
🥭|mangue mango
🍍|ananas pineapple
🥥|noix de coco coconut
🥝|kiwi
🍅|tomate tomato
🥑|avocat avocado
🥦|brocoli broccoli
🥕|carotte carrot
🌽|mais corn
🌶️|piment chili
🥔|patate pomme de terre potato
🥐|croissant
🥖|baguette pain bread
🍞|pain bread
🧀|fromage cheese
🥚|oeuf egg
🍳|oeuf au plat cuisine cooking
🥞|crepes pancakes
🥓|bacon lard
🍗|poulet cuisse chicken
🍖|viande meat
🍔|burger hamburger
🍟|frites fries
🍕|pizza
🌭|hot-dog
🥪|sandwich
🌮|taco
🌯|burrito
🥗|salade salad
🍝|pates spaghetti pasta
🍜|ramen nouilles
🍣|sushi
🍱|bento
🍚|riz rice
🍦|glace italienne ice cream
🍨|glace ice cream
🍩|donut beignet
🍪|cookie biscuit
🎂|gateau anniversaire birthday cake
🍰|part de gateau cake
🧁|cupcake
🍫|chocolat chocolate
🍬|bonbon candy
🍭|sucette lollipop
🍯|miel honey
☕|cafe the coffee tea
🍵|the vert tea
🧃|jus juice
🥤|soda gobelet
🧋|bubble tea
🍺|biere beer
🍻|tchin biere cheers
🥂|champagne trinquer cheers
🍷|vin wine
🥃|whisky
🍸|cocktail
🍾|champagne bouteille
⚽|foot football soccer
🏀|basket basketball
🏈|football americain
⚾|baseball
🎾|tennis
🏐|volley volleyball
🏉|rugby
🎱|billard billiards
🏓|ping-pong
🏸|badminton
🥊|boxe boxing
⛳|golf
🎿|ski
🏂|snowboard
🏆|trophee coupe victoire trophy
🥇|medaille or premier gold
🥈|medaille argent second
🥉|medaille bronze troisieme
🎮|jeu video manette game controller
🕹️|joystick arcade
🎲|de jeu dice
🧩|puzzle
♟️|echecs chess
🎯|cible dans le mille target
🎳|bowling
🎨|peinture art palette
🎬|cinema film clap movie
🎤|micro karaoke mic
🎧|casque musique headphones
🎵|note musique music
🎶|notes musique music
🎹|piano clavier
🥁|batterie tambour drum
🎸|guitare guitar
🎻|violon violin
🎺|trompette trumpet
🚗|voiture car
🚕|taxi
🚌|bus
🚑|ambulance
🚒|pompiers fire engine
🚓|police
🏎️|course voiture race
🏍️|moto motorcycle
🚲|velo bike
🛴|trottinette scooter
🚂|train locomotive
🚆|train
🚇|metro
✈️|avion plane
🚀|fusee rocket lancement
🛸|ovni ufo
🚁|helicoptere
⛵|voilier bateau sailboat
🚢|bateau navire ship
⚓|ancre anchor
🗺️|carte map
🧭|boussole compass
🏔️|montagne mountain
🏖️|plage beach
🏕️|camping
🏠|maison home house
🏢|bureau immeuble office
🏥|hopital hospital
🏫|ecole school
🏰|chateau castle
🗼|tour tower
🗽|statue liberte
⛪|eglise church
🎡|grande roue
🎢|montagnes russes
🌃|nuit ville night
🌅|lever de soleil sunrise
🌇|coucher de soleil sunset
⌚|montre watch
📱|telephone portable smartphone phone
💻|ordinateur portable laptop pc
⌨️|clavier keyboard
🖥️|ecran ordinateur desktop
🖨️|imprimante printer
🖱️|souris mouse
💾|disquette sauvegarde save
💿|cd disque
📷|appareil photo camera
📸|photo flash
🎥|camera video
📺|television tv
📻|radio
⏰|reveil alarme alarm clock
⏳|sablier hourglass
⌛|sablier fin
🔋|batterie battery
🔌|prise plug
💡|ampoule idee light bulb idea
🔦|lampe torche flashlight
🕯️|bougie candle
🗑️|poubelle corbeille trash
💸|argent qui s'envole money
💵|billet dollar money
💶|billet euro money
💳|carte bancaire credit card
💎|diamant gem
⚖️|balance justice
🔧|cle outil wrench
🔨|marteau hammer
🛠️|outils tools
⚙️|engrenage reglages gear settings
🔩|ecrou boulon
🧱|brique brick
🧲|aimant magnet
🔫|pistolet a eau
💣|bombe bomb
🔪|couteau knife
🛡️|bouclier shield
🔮|boule de cristal
🧿|oeil nazar
💊|pilule medicament pill
💉|seringue vaccin syringe
🧬|adn dna
🔬|microscope
🔭|telescope
🧹|balai broom
🧺|panier basket
🧻|papier toilette
🧼|savon soap
🛒|caddie courses shopping cart
🎁|cadeau gift present
🎈|ballon balloon
🎉|fete confettis party tada
🎊|confettis
🎄|sapin de noel christmas tree
🎃|citrouille halloween pumpkin
🎆|feu d'artifice fireworks
🧨|petard firecracker
✉️|enveloppe mail lettre email
📧|email courriel
📨|courrier entrant
📦|colis paquet package box
📝|memo note crayon
📅|calendrier date calendar
📆|calendrier agenda
📌|epingle punaise pin
📎|trombone paperclip
✂️|ciseaux scissors
📏|regle ruler
📐|equerre
📚|livres books
📖|livre ouvert book
🔖|marque-page bookmark
🏷️|etiquette tag label
🔒|cadenas ferme verrouille lock
🔓|cadenas ouvert unlock
🔑|cle key
🔍|loupe recherche search
❤️‍🩹|coeur guerison
✅|valide coche check done
☑️|case cochee
✔️|coche check
❌|croix non erreur cross no
❎|croix carre
➕|plus add
➖|moins minus
➗|diviser divide
✖️|multiplier multiply
❓|question point d'interrogation
❗|exclamation attention
‼️|double exclamation
⚠️|attention avertissement warning
🚫|interdit forbidden
⛔|sens interdit no entry
♻️|recyclage recycle
🔴|rond rouge red circle
🟠|rond orange
🟡|rond jaune
🟢|rond vert green
🔵|rond bleu blue
🟣|rond violet
⚫|rond noir
⚪|rond blanc
🟥|carre rouge
🟩|carre vert
🟦|carre bleu
➡️|fleche droite arrow right
⬅️|fleche gauche arrow left
⬆️|fleche haut arrow up
⬇️|fleche bas arrow down
🔄|actualiser refresh
🔁|repeter repeat
🔀|aleatoire shuffle
▶️|lecture play
⏸️|pause
⏹️|stop
⏭️|suivant next
🔊|son fort volume loud
🔇|muet mute
🔔|cloche notification bell
🔕|silence pas de cloche
📢|haut-parleur annonce
🆗|ok
🆕|nouveau new
🆒|cool
🆓|gratuit free
🔞|moins de 18
©️|copyright
®️|marque deposee registered
™️|trademark
#️⃣|diese hashtag
🇫🇷|france drapeau francais flag
🇧🇪|belgique drapeau flag
🇨🇭|suisse drapeau flag
🇨🇦|canada quebec drapeau flag
🇬🇧|royaume-uni angleterre uk flag
🇺🇸|etats-unis usa flag
🇩🇪|allemagne germany flag
🇪🇸|espagne spain flag
🇮🇹|italie italy flag
🇯🇵|japon japan flag
🇪🇺|europe union europeenne flag
🏳️‍🌈|arc-en-ciel lgbt pride flag
🏁|drapeau a damier course finish
🚩|drapeau rouge red flag`;

const norm = s => s.normalize('NFD').replace(/\p{Diacritic}/gu, '').toLowerCase();

export const EMOJI = RAW.split('\n').map(l => {
  const [e, words] = l.split('|');
  return { e, words: norm(words) };
});

export function searchEmoji(q) {
  q = norm(q.trim());
  if (!q) return EMOJI;
  const parts = q.split(/\s+/);
  return EMOJI
    .map(x => {
      const ws = x.words.split(' ');
      let score = 0;
      for (const p of parts) {
        if (ws.some(w => w === p)) score += 3;
        else if (ws.some(w => w.startsWith(p))) score += 2;
        else if (x.words.includes(p)) score += 1;
        else return null;
      }
      return { x, score };
    })
    .filter(Boolean)
    .sort((a, b) => b.score - a.score)
    .map(r => r.x);
}
