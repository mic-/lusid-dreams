.global _SONG_POINTERS
.global _SONG_SIZES
.global _NUM_SONGS

.section .text

.align 2

SONG1:  .incbin "songs/1992.sid"
SONG2: .incbin "songs/3rd_Stone_from_Sun_part_1.sid"
SONG3:  .incbin "songs/7_on_the_Top.sid"
SONG4:  .incbin "songs/7_Runes.sid"
SONG5: .incbin "songs/A_Theory_of_Space_and_Starships.sid"
SONG6:  .incbin "songs/Aces_High.sid"
SONG7: .incbin "songs/Afterburner.sid"
SONG8:  .incbin "songs/Another.sid"
SONG9: .incbin "songs/Aquanori.sid"
SONG10: .incbin "songs/Austria_Party_2.sid"
SONG11: .incbin "songs/Cartilage_tune_2.sid"
SONG12:  .incbin "songs/Compilation_III.sid"
SONG13:  .incbin "songs/DNA-Dream.sid"
SONG14:  .incbin "songs/Driller.sid"
SONG15: .incbin "songs/Galway-tune.sid"
SONG16: .incbin "songs/Gauntlet_III.sid"
SONG17: .incbin "songs/Good_Enough.sid"
SONG18: .incbin "songs/Hawkeye_loader.sid"
SONG19: .incbin "songs/Ikari_Union.sid"
SONG20:  .incbin "songs/Kinetix.sid"  !Contest_Demo_part_2.sid"
SONG21: .incbin "songs/Knight_Rider_2.sid"
SONG22: .incbin "songs/Last_Rock.sid"
SONG23: .incbin "songs/Lazy_Business.sid"
SONG24: .incbin "songs/Magic_Flute.sid"
SONG25: .incbin "songs/Mogne_Molnar.sid"  
SONG26: .incbin "songs/Music_for_Your_Ears.sid"
SONG27: .incbin "songs/Nag_Champa.sid"
SONG28: .incbin "songs/Nintendo_Metal.sid"   
SONG29: .incbin "songs/Noisy_Pillars.sid"
SONG30: .incbin "songs/Ocean_Loader_3.sid"
SONG31: .incbin "songs/One_Man_and_His_Droid.sid"
SONG32: .incbin "songs/Outrun_Europe_levels.sid"
SONG33: .incbin "songs/Playboy_the_Game.sid"
SONG34: .incbin "songs/R-Type.sid"
SONG35: .incbin "songs/Rendez-Vous_4_v2.sid"
SONG36: .incbin "songs/Rise_and_Sine.sid"  
SONG37: .incbin "songs/Sagyrs_Castle.sid"  
SONG38: .incbin "songs/Shadow_of_the_Beast_demo.sid"  
SONG39: .incbin "songs/Supremacy.sid"
SONG40: .incbin "songs/Tarzan_Goes_Ape.sid"
 SONG41: .incbin "songs/Telephone.sid"  
SONG42: .incbin "songs/Consultant.sid"
SONG43: .incbin "songs/Traegen_Vinner.sid"
 SONG44: .incbin "songs/Turrican.sid"
SONG45: .incbin "songs/Turrican_32k.sid"
SONG46: .incbin "songs/We_Laser.sid"
SONG47: .incbin "songs/Victim_of_Lulu.sid"
SONG48: .incbin "songs/Victory.sid"
SONG49: .incbin "songs/Yie_Ar_Kung_Fu.sid"
SONG50: .incbin "songs/Zoids.sid"


SONGS_END:

.align 2
_SONG_POINTERS:
.long SONG1
.long SONG2
.long SONG3
.long SONG4
.long SONG5
.long SONG6
.long SONG7
.long SONG8
.long SONG9
.long SONG10
.long SONG11
.long SONG12
.long SONG13
.long SONG14
.long SONG15
.long SONG16
.long SONG17
.long SONG18
.long SONG19
.long SONG20
.long SONG21
.long SONG22
.long SONG23
.long SONG24
.long SONG25
.long SONG26
.long SONG27
.long SONG28
.long SONG29
.long SONG30
.long SONG31
.long SONG32
.long SONG33
.long SONG34
.long SONG35
.long SONG36
.long SONG37
.long SONG38
.long SONG39
.long SONG40
.long SONG41
.long SONG42
.long SONG43
.long SONG44
.long SONG45
.long SONG46
.long SONG47
.long SONG48
.long SONG49
.long SONG50

_SONG_SIZES:
.long SONG2 - SONG1
.long SONG3 - SONG2
.long SONG4 - SONG3
.long SONG5 - SONG4
.long SONG6 - SONG5
.long SONG7 - SONG6
.long SONG8 - SONG7
.long SONG9 - SONG8
.long SONG10 - SONG9
.long SONG11 - SONG10
.long SONG12 - SONG11
.long SONG13 - SONG12
.long SONG14 - SONG13
.long SONG15 - SONG14
.long SONG16 - SONG15
.long SONG17 - SONG16
.long SONG18 - SONG17
.long SONG19 - SONG18
.long SONG20 - SONG19
.long SONG21 - SONG20
.long SONG22 - SONG21
.long SONG23 - SONG22
.long SONG24 - SONG23
.long SONG25 - SONG24
.long SONG26 - SONG25
.long SONG27 - SONG26
.long SONG28 - SONG27
.long SONG29 - SONG28
.long SONG30 - SONG29
.long SONG31 - SONG30
.long SONG32 - SONG31
.long SONG33 - SONG32
.long SONG34 - SONG33
.long SONG35 - SONG34
.long SONG36 - SONG35
.long SONG37 - SONG36
.long SONG38 - SONG37
.long SONG39 - SONG38
.long SONG40 - SONG39
.long SONG41 - SONG40
.long SONG42 - SONG41
.long SONG43 - SONG42
.long SONG44 - SONG43
.long SONG45 - SONG44
.long SONG46 - SONG45
.long SONG47 - SONG46
.long SONG48 - SONG47
.long SONG49 - SONG48
.long SONG50 - SONG49
.long SONGS_END - SONG50

_NUM_SONGS:
.long (_SONG_SIZES - _SONG_POINTERS) / 4

.align 2
