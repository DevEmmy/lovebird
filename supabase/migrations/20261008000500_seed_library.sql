-- =====================================================================
-- Lovebird 0005 — Library seed: Lovebird Originals + public-domain poetry.
-- Only original or public-domain text ships here (brief §20).
-- =====================================================================

do $$
declare b uuid;
begin
  -- -------------------------------------------------------------------
  insert into public.books (title, author, description, cover_color, category, license, tags, published)
  values ('The Clock Between Us', 'Lovebird Originals',
          'Lagos and Toronto are five hours apart. Ada and Tomi decide that is not the same thing as being apart.',
          '#C2185B', 'original', 'original', '{long-distance,romance,short}', true)
  returning id into b;
  insert into public.book_chapters (book_id, number, title, body) values
  (b, 1, 'Two Clocks', $t$Ada kept two clocks on her desk. The first was the one everyone in Lagos had: honest, loud, permanently ten minutes fast because her mother had set it that way in 2014 and nobody had dared to touch it since. The second clock was small and white and set five hours behind. It was Tomi's clock.

"You know your phone can do this," Tomi said on the first night she showed him. His face filled the screen, pixelated at the edges, the light behind him the colour of an evening that had not reached her yet.

"My phone can do a lot of things," Ada said. "It cannot sit on my desk and be yours."

He laughed, the kind of laugh that started in his shoulders before it reached his mouth, and she decided she had been right to buy it.

The rule was simple. When Ada woke up, she looked at the white clock and guessed what he was doing. Two in the morning: asleep, probably on his stomach, probably with one sock off. Seven in the evening: walking home from the library, earphones in, pretending not to be cold. She wrote her guesses down in a notebook, and on Sundays they compared.

She was right more often than he liked.

"It's unsettling," he said. "You've built a model of me."

"I've built a model of us," she corrected. "You're just the part that lives in a different time zone."$t$),
  (b, 2, 'The Overlap', $t$There were three hours every day when they were both awake and neither of them was working. They called it the Overlap, and they guarded it like a country guards its border.

In the Overlap they cooked the same meal: jollof on both ends of the call, his always a little too wet, hers always a little too proud. They watched the same terrible films and paused them at the same moment to argue about whether the main character deserved forgiveness. They read the same chapter of the same book and fought, gently, about the ending.

Sometimes they did nothing at all. Ada would fall asleep with the call still running, and Tomi would listen to the fan in her room turn and turn, and he would finish his reading to the sound of it.

"Is that weird?" he asked once. "That I like listening to you sleep?"

"It's weird," Ada agreed, eyes closed. "Keep doing it."

The Overlap was not enough. They both knew that. But it was theirs, and it was built on purpose, and on the nights when the distance felt like a physical thing pressing on Ada's chest, she would look at the white clock and think: he is in there, five hours ago, walking towards me.$t$),
  (b, 3, 'Same Time Zone', $t$The ticket was for a Thursday. Ada had wanted a Saturday, for the symmetry, but Thursday was cheaper and Tomi said symmetry was a luxury for people who did not pay rent.

On the flight she did not sleep. She held the white clock in her lap, and somewhere over the Atlantic, she reached into the back of it and turned the little wheel. One hour. Two. She stopped at four, because the plane was still in the air and she did not want to arrive early, even in theory.

He was at the barrier with a sign that said ADA in letters so large they were almost rude. He was wearing both socks. She checked.

"Hi," he said, which was a stupid thing to say after eleven months, and also the only thing.

"Hi," she said, and held up the white clock. The last hour was still left. "Will you do it?"

He took it from her carefully, like it was something that might wake up. He turned the wheel until the hands matched the big clock on the arrivals board, and then he gave it back.

"There," he said. "Same time."

They would go back to two clocks in nine days. They both knew that too. But Ada kept the white clock on Toronto time for the whole visit, and on the flight home she did not change it back for a long while.$t$);

  -- -------------------------------------------------------------------
  insert into public.books (title, author, description, cover_color, category, license, tags, published)
  values ('Letters from the Lighthouse', 'Lovebird Originals',
          'A lighthouse keeper and a radio operator fall in love one sentence at a time, sixty seconds per night.',
          '#AD1457', 'original', 'original', '{letters,slow-burn,short}', true)
  returning id into b;
  insert into public.book_chapters (book_id, number, title, body) values
  (b, 1, 'Sixty Seconds', $t$The regulations gave Mara sixty seconds of open radio every night at nine. It was meant for weather. For the first month, she used it for weather.

"Wind north-north-east, twelve knots. Visibility good. Nothing to report."

On the thirty-third night, a voice came back that was not the coastguard.

"Nothing at all? Not even a nice cloud?"

Mara stared at the receiver. Regulations did not cover nice clouds.

"There was one," she said finally, "shaped like a teapot."

"Thank you," said the voice. "That's the best thing anyone's told me all week." And the sixty seconds ran out.

His name, she learned over the next fortnight, was Ilan. He ran the relay station on the mainland, alone, the way she ran the light. He had a dog that was afraid of seagulls and a kettle that whistled in a minor key. He learned that she had read every book in the lighthouse twice and was starting on the instruction manuals.

Sixty seconds is not a long time. It turns out you can fall in love in it anyway, if you do it a minute at a time.$t$),
  (b, 2, 'The Storm Night', $t$The storm came in on a Tuesday. By nine, the waves were throwing themselves against the rocks with a sound like furniture being moved in heaven, and the radio was mostly static.

"Mara?" His voice came through in pieces. "Mara, are you—"

"I'm fine," she said, though the light was shuddering in its housing and she had not sat down in four hours. "Wind west, forty knots. Visibility—" A wave hit. "Visibility: rude."

Static. Then, faintly: "Talk to me. Use the whole minute. Regulations be damned."

So she did. She told him about the teapot cloud and the instruction manuals and how she had started saving the best sentences of her day for nine o'clock, like sweets in a pocket. She told him she didn't know what his face looked like and found she didn't mind. She was still talking when the minute ended, and she kept talking into the dead radio for a long while after, because the storm was loud and it helped.

At five past nine, the receiver crackled. It was against every rule he had.

"I heard all of it," Ilan said. "Every word. The relay picks up the overflow." A pause. "I save my best sentences too."$t$),
  (b, 3, 'The Boat', $t$In spring the supply boat came, and there was someone on it who was not the supply man.

He was taller than she had pictured and shorter than he had described, and the dog came too, and the dog immediately saw a seagull and hid behind Mara's legs.

"He likes you," Ilan said.

"He's using me as a shield."

"That's how he shows it."

They stood on the jetty and did not know what to do with their hands. They had only ever had sixty seconds. Now they had a whole afternoon, a whole spring, and it was almost too much.

"Wind," Mara said finally, because she had to say something. "Light. South-westerly."

"Visibility?" Ilan asked.

She looked at him properly for the first time.

"Good," she said. "Very good."

At nine that night, out of habit, they both looked at the radio. Then Ilan turned it off, and they used the whole minute, and the one after it, and every one after that.$t$);

  -- -------------------------------------------------------------------
  insert into public.books (title, author, description, cover_color, category, license, tags, published)
  values ('Love Poems for Two', 'Various (public domain)',
          'Five classic love poems to read aloud to each other — one per night, or all at once.',
          '#880E4F', 'poetry', 'public_domain', '{poetry,classic,read-aloud}', true)
  returning id into b;
  insert into public.book_chapters (book_id, number, title, body) values
  (b, 1, 'Sonnet 18 — William Shakespeare (1609)', $t$Shall I compare thee to a summer's day?
Thou art more lovely and more temperate:
Rough winds do shake the darling buds of May,
And summer's lease hath all too short a date;
Sometime too hot the eye of heaven shines,
And often is his gold complexion dimm'd;
And every fair from fair sometime declines,
By chance or nature's changing course untrimm'd;
But thy eternal summer shall not fade,
Nor lose possession of that fair thou ow'st;
Nor shall Death brag thou wander'st in his shade,
When in eternal lines to time thou grow'st:
So long as men can breathe or eyes can see,
So long lives this, and this gives life to thee.$t$),
  (b, 2, 'Sonnet 43 — Elizabeth Barrett Browning (1850)', $t$How do I love thee? Let me count the ways.
I love thee to the depth and breadth and height
My soul can reach, when feeling out of sight
For the ends of being and ideal grace.
I love thee to the level of every day's
Most quiet need, by sun and candle-light.
I love thee freely, as men strive for right.
I love thee purely, as they turn from praise.
I love thee with the passion put to use
In my old griefs, and with my childhood's faith.
I love thee with a love I seemed to lose
With my lost saints. I love thee with the breath,
Smiles, tears, of all my life; and, if God choose,
I shall but love thee better after death.$t$),
  (b, 3, 'A Red, Red Rose — Robert Burns (1794)', $t$O my Luve is like a red, red rose
   That's newly sprung in June;
O my Luve is like the melody
   That's sweetly play'd in tune.

So fair art thou, my bonnie lass,
   So deep in luve am I;
And I will luve thee still, my dear,
   Till a' the seas gang dry.

Till a' the seas gang dry, my dear,
   And the rocks melt wi' the sun;
I will love thee still, my dear,
   While the sands o' life shall run.

And fare thee weel, my only luve!
   And fare thee weel awhile!
And I will come again, my luve,
   Though it were ten thousand mile.$t$),
  (b, 4, 'She Walks in Beauty — Lord Byron (1815)', $t$She walks in beauty, like the night
Of cloudless climes and starry skies;
And all that's best of dark and bright
Meet in her aspect and her eyes;
Thus mellowed to that tender light
Which heaven to gaudy day denies.

One shade the more, one ray the less,
Had half impaired the nameless grace
Which waves in every raven tress,
Or softly lightens o'er her face;
Where thoughts serenely sweet express,
How pure, how dear their dwelling-place.

And on that cheek, and o'er that brow,
So soft, so calm, yet eloquent,
The smiles that win, the tints that glow,
But tell of days in goodness spent,
A mind at peace with all below,
A heart whose love is innocent!$t$),
  (b, 5, 'Sonnet 116 — William Shakespeare (1609)', $t$Let me not to the marriage of true minds
Admit impediments. Love is not love
Which alters when it alteration finds,
Or bends with the remover to remove.
O no! it is an ever-fixed mark
That looks on tempests and is never shaken;
It is the star to every wand'ring bark,
Whose worth's unknown, although his height be taken.
Love's not Time's fool, though rosy lips and cheeks
Within his bending sickle's compass come;
Love alters not with his brief hours and weeks,
But bears it out even to the edge of doom.
If this be error and upon me proved,
I never writ, nor no man ever loved.$t$);

  -- -------------------------------------------------------------------
  insert into public.books (title, author, description, cover_color, category, license, tags, published)
  values ('52 Letters', 'Lovebird Originals',
          'An interactive book: each chapter is a prompt. You both write a letter, then reveal them together.',
          '#D81B60', 'interactive', 'original', '{interactive,letters,prompts}', true)
  returning id into b;
  insert into public.book_chapters (book_id, number, title, body) values
  (b, 1, 'The First Time I Noticed You', $t$Write about the very first moment you noticed your partner. Not when you fell for them — just when they first came into focus. What were they wearing? What did you think? What did you get wrong about them?

When you're done, answer the chapter question below. Your partner won't see your letter until they've written theirs.$t$),
  (b, 2, 'A Small Thing You Do', $t$Choose one small, ordinary thing your partner does that they probably don't know you love. The way they say goodnight. How they type when they're excited. The face they make at bad food.

Describe it so precisely that they'll recognise themselves instantly.$t$),
  (b, 3, 'Our Future Kitchen', $t$Imagine a kitchen you will share one day. What's on the fridge? Who cooks, who cleans, who steals food off the other's plate? What song is playing?

Be specific. Be ridiculous if you want to. This one is supposed to be fun.$t$),
  (b, 4, 'When It Was Hard', $t$Write about a moment in your relationship that was difficult — and what your partner did, or didn't do, that helped you through it.

Be honest and be kind. The goal isn't to reopen anything. It's to say: I saw what you did, and it mattered.$t$);
end $$;
