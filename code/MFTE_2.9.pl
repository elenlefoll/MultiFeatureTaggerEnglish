#!/usr/bin/perl
# -*-cperl-*-

## Multi-Feature Tagger of English (MFTE) by Elen Le Foll (ELF) - For tagging a range of lexico-grammatical features and counting the tags (suitable for full multi-dimensional analyses; MDAs).

## Originally based on a cross-platform version of Andrea Nini's Multidimensional Analysis Tagger (MAT) which is, itself, an open-source replication of the Biber Tagger (1988)

## This code was formally evaluated on perl 5, version 22, subversion 1 (v5.22.1) built for x86_64-linux-gnu-thread-multi 
## It was additionally tested on perl 5, version 30, subversion 2 (v5.30.2) built for darwin-thread-multi-2level

$| = 1;

use FindBin qw($RealBin);
use File::Temp;

# The following four lines were kindly contributed by Peter Uhrig (see also line 1355)
#use utf8;
#use open OUT => ':encoding(UTF-8)';
#use open IN => ':encoding(UTF-8)';
#use open IO => ':encoding(UTF-8)';

die <<EOT unless @ARGV == 3 || @ARGV == 4;

Multi-Feature Tagger of English (MFTE) v. 2.9

***

Please cite as: 
Le Foll, Elen (2021). A Multi-Feature Tagger of English (MFTE). Software v. 2.9. 
Available under a GPL-3.0 License on: https://github.com/elenlefoll/MultiFeatureTaggerEnglish

Code based on the Multidimensional Analysis Tagger v. 1.3 by Andrea Nini [https://sites.google.com/site/multidimensionaltagger/]:
Nini, Andrea (2019). The Muli-Dimensional Analysis Tagger. In Berber Sardinha, T. & Veirano Pinto M. (eds), Multi-Dimensional Analysis: Research Methods and Current Issues, 67-94, London; New York: Bloomsbury Academic. 

Requires the separate installation of the Stanford Tagger for English [http://nlp.stanford.edu/software/tagger.shtml]:
Kristina Toutanova, Dan Klein, Christopher Manning, & Yoram Singer (2003). Feature-Rich Part-of-Speech Tagging with a Cyclic Dependency Network. In Proceedings of HLT-NAACL 2003: pp. 252-259. 

***

Usage:  perl MFTE_2.9.pl input_txt/ tagged_txt/ prefix [TTRsize]

The folder input_txt/ must contain the corpus texts as separate files in plain text format.  All files in the folder will be processed, regardless of their extension.  Tagged texts are stored under the same names in the folder tagged_txt/, and feature counts are extracted as TAB-separated tables:

    <prefix>_counts.tsv   relative frequencies

[TTRsize] may be replaced by the number of tokens for which the type-token ration is to be computed; it should be less than the shortest text in the corpus (if no value is entered the default is 400, as in Biber 1988).

Note that this script only tags and computes a count tally of all the features. It does not compute any dimensions. See corresponding .Rmd file to do so.

EOT

our ($InputDir, $OutputDir, $Prefix, $TokensForTTR, $NormBasis) = @ARGV;
$TokensForTTR = 400 unless $TokensForTTR;
$NormBasis = 1 unless $NormBasis;

unless (-d $OutputDir) {
  mkdir $OutputDir or die "Can't create output directory $OutputDir/: $!";
}
die "Error: $OutputDir exists but isn't a directory\n" unless -d $OutputDir;

run_tagger($InputDir, $OutputDir);
do_counts($Prefix, $OutputDir, $TokensForTTR);

print "Feature tagging and counting complete. Share and enjoy!\n";

############################################################
## Run Stanford tagger efficiently over all texts and post-process files
## This section of the code was kindly provided by Stephanie Evert (SE)
##   run_tagger($input_dir, $tagged_dir);
sub run_tagger {
  my ($input_dir, $tagged_dir) = @_;
  
  opendir(DIR, $input_dir) or die "Can't read directory $input_dir/: $!";
  my @filenames = grep {-f "$input_dir/$_"} readdir(DIR);
  close(DIR);
  ## @filenames = @filenames[0 .. 99] if (@filenames > 100); # for TESTING
  my $n_files = @filenames;

  my $Temp = new File::Temp SUFFIX => ".txt.gz";
  my $tempfile = $Temp->filename;
  
  ## run Stanford Tagger efficiently by concatenating text from all files
  my $tagger_cmd = "java -mx2g -classpath 'stanford-postagger-2018-10-16/stanford-postagger.jar' edu.stanford.nlp.tagger.maxent.MaxentTagger -model 'stanford-postagger-2018-10-16/models/english-bidirectional-distsim.tagger'  | gzip > '$tempfile'";
#  my $tagger_cmd = "java -mx300m -classpath 'stanford-postagger-2018-10-16/stanford-postagger.jar' edu.stanford.nlp.tagger.maxent.MaxentTagger -model 'stanford-postagger-2018-10-16/models/english-bidirectional-distsim.tagger' 2>/dev/null | gzip > '$tempfile'";
  open(PIPE, "| $tagger_cmd") or die "Can't run StanfordTagger: $!";
  printf " -> running StanfordTagger on %d files\r", $n_files;
  foreach my $n (0 .. $n_files - 1) {
    print STDERR "Processing file $input_dir/$filenames[$n]\n";
    printf PIPE "matagger%08d\n", $n;
    open(FH, "$input_dir/$filenames[$n]") or die "Can't read input file $input_dir/$filenames[$n]: $!";
    print PIPE <FH>;
    close(FH);
    print PIPE "\n";
#    printf "%8d / %d texts sent to StanfordTagger\r", $n + 1, $n_files;
  }
  close(PIPE);
  print " " x 60, "\r";

  ## extract texts from compressed temporary files and apply post-processing
  my $current_n = -1;
  my $n_tokens = 0;
  open(PIPE, "gzip -cd '$tempfile' |") or die "Can't read temporary file $tempfile: $!";
  while (<PIPE>) {
    if (/^matagger(\d+)_\S+$/) {
      my $n = $1;
      die sprintf "Error: found text #%d, but expected #%d (line #%d)\n", $n, $current_n + 1, $. unless $n == $current_n + 1;
      close(FH) if $current_n >= 0;
      open(FH, "> $tagged_dir/$filenames[$n]") or die "Can't write output file $tagged_dir/$filenames[$n]: $!";
      $current_n = $n;
      printf "%8d / %d texts post-processed\r", $current_n, $n_files;
    }
    else {
      chomp;
      die "Format error on line #$.: $_" if /matagger\d+/;
      my @words = split;
      if (@words > 0) {
        my @tagged = process_sentence(@words);
        foreach (@tagged) {
          print FH "$_\n";
        }
        print FH "\n"; # blank line after each sentence
        $n_tokens += @tagged;
      }
    }
  }
  close(FH) if $current_n >= 0;
  die sprintf "Error: wrong number of texts (found %d, but expected %d)\n", $current_n + 1, $n_files unless $current_n + 1 == $n_files;
  
  print " " x 60, "\r";
  printf "Processed %d texts with %.1fM tokens\n", $n_files, $n_tokens / 1e6;
}

############################################################
## Post-process tagged sentences (as lists of words)

sub process_sentence {
  my @word = @_;

  # DICTIONARY LISTS
  
  $have = "have_V|has_V|ve_V|had_V|having_V|hath_|s_VBZ|d_V"; # ELF: added s_VBZ, added d_VBD, e.g. "he's got, he's been and he'd been" ELF: Also removed all the apostrophes in Nini's lists because they don't work in combination with \b in regex as used extensively in this script.
 
  $do ="do_V|does_V|did_V|done_V|doing_V|doing_P|done_P"; 
 
  $be = "be_V|am_V|is_V|are_V|was_V|were_V|been_V|being_V|s_VBZ|m_V|re_V|been_P"; # ELF: removed apostrophes and added "been_P" to account for the verb "be" when tagged as occurrences of passive or perfect forms (PASS and PEAS tags).
 
  $who = "what_|where_|when_|how_|whether_|why_|whoever_|whomever_|whichever_|wherever_|whenever_|whatever_"; # ELF: Removed "however" from Nini/Biber's original list.
 
  $wp = "who_|whom_|whose_|which_";
 
  # ELF: added this list for new WH-question variable:  
  $whw = "what_|where_|when_|how_|why_|who_|whom_|whose_|which_"; 
 
  $preposition = "about_|against_|amid_|amidst_|among_|amongst_|at_|between_|by_|despite_|during_|except_|for_|from_|in_|into_|minus_|of_|off_|on_|onto_|opposite_|out_|per_|plus_|pro_|than_|through_|throughout_|thru_|toward_|towards_|upon_|versus_|via_|with_|within_|without_"; # ELF: removed "besides".
  
  # ELF: Added this new list but it currently not in use.
  #$particles =
#"about|above|across|ahead|along|apart|around|aside|at|away|back|behind|between|by|down|forward|from|in|into|off|on|out|over|past|through|to|together|under|up|upon|with|without"; 

  # ELF: The next three lists of semantic categories of verbs are taken from Biber 1988; however, the current version of the script uses the verb semantic categories from Biber 2006 instead, but the following three lists are still used for some variables, e.g. THATD.
  $public = "acknowledge_V|acknowledged_V|acknowledges_V|acknowledging_V|add_V|adds_V|adding_V|added_V|admit_V|admits_V|admitting_V|admitted_V|affirm_V|affirms_V|affirming_V|affirmed_V|agree_V|agrees_V|agreeing_V|agreed_V|allege_V|alleges_V|alleging_V|alleged_V|announce_V|announces_V|announcing_V|announced_V|argue_V|argues_V|arguing_V|argued_V|assert_V|asserts_V|asserting_V|asserted_V|bet_V|bets_V|betting_V|boast_V|boasts_V|boasting_V|boasted_V|certify_V|certifies_V|certifying_V|certified_V|claim_V|claims_V|claiming_V|claimed_V|comment_V|comments_V|commenting_V|commented_V|complain_V|complains_V|complaining_V|complained_V|concede_V|concedes_V|conceding_V|conceded_V|confess_V|confesses_V|confessing_V|confessed_V|confide_V|confides_V|confiding_V|confided_V|confirm_V|confirms_V|confirming_V|confirmed_V|contend_V|contends_V|contending_V|contended_V|convey_V|conveys_V|conveying_V|conveyed_V|declare_V|declares_V|declaring_V|declared_V|deny_V|denies_V|denying_V|denied_V|disclose_V|discloses_V|disclosing_V|disclosed_V|exclaim_V|exclaims_V|exclaiming_V|exclaimed_V|explain_V|explains_V|explaining_V|explained_V|forecast_V|forecasts_V|forecasting_V|forecasted_V|foretell_V|foretells_V|foretelling_V|foretold_V|guarantee_V|guarantees_V|guaranteeing_V|guaranteed_V|hint_V|hints_V|hinting_V|hinted_V|insist_V|insists_V|insisting_V|insisted_V|maintain_V|maintains_V|maintaining_V|maintained_V|mention_V|mentions_V|mentioning_V|mentioned_V|object_V|objects_V|objecting_V|objected_V|predict_V|predicts_V|predicting_V|predicted_V|proclaim_V|proclaims_V|proclaiming_V|proclaimed_V|promise_V|promises_V|promising_V|promised_V|pronounce_V|pronounces_V|pronouncing_V|pronounced_V|prophesy_V|prophesies_V|prophesying_V|prophesied_V|protest_V|protests_V|protesting_V|protested_V|remark_V|remarks_V|remarking_V|remarked_V|repeat_V|repeats_V|repeating_V|repeated_V|reply_V|replies_V|replying_V|replied_V|report_V|reports_V|reporting_V|reported_V|say_V|says_V|saying_V|said_V|state_V|states_V|stating_V|stated_V|submit_V|submits_V|submitting_V|submitted_V|suggest_V|suggests_V|suggesting_V|suggested_V|swear_V|swears_V|swearing_V|swore_V|sworn_V|testify_V|testifies_V|testifying_V|testified_V|vow_V|vows_V|vowing_V|vowed_V|warn_V|warns_V|warning_V|warned_V|write_V|writes_V|writing_V|wrote_V|written_V";
  $private = "accept_V|accepts_V|accepting_V|accepted_V|anticipate_V|anticipates_V|anticipating_V|anticipated_V|ascertain_V|ascertains_V|ascertaining_V|ascertained_V|assume_V|assumes_V|assuming_V|assumed_V|believe_V|believes_V|believing_V|believed_V|calculate_V|calculates_V|calculating_V|calculated_V|check_V|checks_V|checking_V|checked_V|conclude_V|concludes_V|concluding_V|concluded_V|conjecture_V|conjectures_V|conjecturing_V|conjectured_V|consider_V|considers_V|considering_V|considered_V|decide_V|decides_V|deciding_V|decided_V|deduce_V|deduces_V|deducing_V|deduced_V|deem_V|deems_V|deeming_V|deemed_V|demonstrate_V|demonstrates_V|demonstrating_V|demonstrated_V|determine_V|determines_V|determining_V|determined_V|discern_V|discerns_V|discerning_V|discerned_V|discover_V|discovers_V|discovering_V|discovered_V|doubt_V|doubts_V|doubting_V|doubted_V|dream_V|dreams_V|dreaming_V|dreamt_V|dreamed_V|ensure_V|ensures_V|ensuring_V|ensured_V|establish_V|establishes_V|establishing_V|established_V|estimate_V|estimates_V|estimating_V|estimated_V|expect_V|expects_V|expecting_V|expected_V|fancy_V|fancies_V|fancying_V|fancied_V|fear_V|fears_V|fearing_V|feared_V|feel_V|feels_V|feeling_V|felt_V|find_V|finds_V|finding_V|found_V|foresee_V|foresees_V|foreseeing_V|foresaw_V|forget_V|forgets_V|forgetting_V|forgot_V|forgotten_V|gather_V|gathers_V|gathering_V|gathered_V|guess_V|guesses_V|guessing_V|guessed_V|hear_V|hears_V|hearing_V|heard_V|hold_V|holds_V|holding_V|held_V|hope_V|hopes_V|hoping_V|hoped_V|imagine_V|imagines_V|imagining_V|imagined_V|imply_V|implies_V|implying_V|implied_V|indicate_V|indicates_V|indicating_V|indicated_V|infer_V|infers_V|inferring_V|inferred_V|insure_V|insures_V|insuring_V|insured_V|judge_V|judges_V|judging_V|judged_V|know_V|knows_V|knowing_V|knew_V|known_V|learn_V|learns_V|learning_V|learnt_V|learned_V|mean_V|means_V|meaning_V|meant_V|note_V|notes_V|noting_V|noted_V|notice_V|notices_V|noticing_V|noticed_V|observe_V|observes_V|observing_V|observed_V|perceive_V|perceives_V|perceiving_V|perceived_V|presume_V|presumes_V|presuming_V|presumed_V|presuppose_V|presupposes_V|presupposing_V|presupposed_V|pretend_V|pretend_V|pretending_V|pretended_V|prove_V|proves_V|proving_V|proved_V|realize_V|realise_V|realising_V|realizing_V|realises_V|realizes_V|realised_V|realized_V|reason_V|reasons_V|reasoning_V|reasoned_V|recall_V|recalls_V|recalling_V|recalled_V|reckon_V|reckons_V|reckoning_V|reckoned_V|recognize_V|recognise_V|recognizes_V|recognises_V|recognizing_V|recognising_V|recognized_V|recognised_V|reflect_V|reflects_V|reflecting_V|reflected_V|remember_V|remembers_V|remembering_V|remembered_V|reveal_V|reveals_V|revealing_V|revealed_V|see_V|sees_V|seeing_V|saw_V|seen_V|sense_V|senses_V|sensing_V|sensed_V|show_V|shows_V|showing_V|showed_V|shown_V|signify_V|signifies_V|signifying_V|signified_V|suppose_V|supposes_V|supposing_V|supposed_V|suspect_V|suspects_V|suspecting_V|suspected_V|think_V|thinks_V|thinking_V|thought_V|understand_V|understands_V|understanding_V|understood_V";
  $suasive = "agree_V|agrees_V|agreeing_V|agreed_V|allow_V|allows_V|allowing_V|allowed_V|arrange_V|arranges_V|arranging_V|arranged_V|ask_V|asks_V|asking_V|asked_V|beg_V|begs_V|begging_V|begged_V|command_V|commands_V|commanding_V|commanded_V|concede_V|concedes_V|conceding_V|conceded_V|decide_V|decides_V|deciding_V|decided_V|decree_V|decrees_V|decreeing_V|decreed_V|demand_V|demands_V|demanding_V|demanded_V|desire_V|desires_V|desiring_V|desired_V|determine_V|determines_V|determining_V|determined_V|enjoin_V|enjoins_V|enjoining_V|enjoined_V|ensure_V|ensures_V|ensuring_V|ensured_V|entreat_V|entreats_V|entreating_V|entreated_V|grant_V|grants_V|granting_V|granted_V|insist_V|insists_V|insisting_V|insisted_V|instruct_V|instructs_V|instructing_V|instructed_V|intend_V|intends_V|intending_V|intended_V|move_V|moves_V|moving_V|moved_V|ordain_V|ordains_V|ordaining_V|ordained_V|order_V|orders_V|ordering_V|ordered_V|pledge_V|pledges_V|pledging_V|pledged_V|pray_V|prays_V|praying_V|prayed_V|prefer_V|prefers_V|preferring_V|preferred_V|pronounce_V|pronounces_V|pronouncing_V|pronounced_V|propose_V|proposes_V|proposing_V|proposed_V|recommend_V|recommends_V|recommending_V|recommended_V|request_V|requests_V|requesting_V|requested_V|require_V|requires_V|requiring_V|required_V|resolve_V|resolves_V|resolving_V|resolved_V|rule_V|rules_V|ruling_V|ruled_V|stipulate_V|stipulates_V|stipulating_V|stipulated_V|suggest_V|suggests_V|suggesting_V|suggested_V|urge_V|urges_V|urging_V|urged_V|vote_V|votes_V|voting_V|voted_V";
  
  # The following lists are based on the verb semantic categories used in Biber 2006.
  # ELF: With many thanks to Muhammad Shakir for providing me with these lists.
  
  # Activity verbs 
  # ELF: removed GET and GO due to high polysemy and corrected the "evercise" typo found in both Shakir and Biber 2006.
  $vb_act =	"(buy|buys|buying|bought|make|makes|making|made|give|gives|giving|gave|given|take|takes|taking|took|taken|come|comes|coming|came|use|uses|using|used|leave|leaves|leaving|left|show|shows|showing|showed|shown|try|tries|trying|tried|work|works|wrought|worked|working|move|moves|moving|moved|follow|follows|following|followed|put|puts|putting|pay|pays|paying|paid|bring|brings|bringing|brought|meet|meets|met|play|plays|playing|played|run|runs|running|ran|hold|holds|holding|held|turn|turns|turning|turned|send|sends|sending|sent|sit|sits|sitting|sat|wait|waits|waiting|waited|walk|walks|walking|walked|carry|carries|carrying|carried|lose|loses|losing|lost|eat|eats|ate|eaten|eating|watch|watches|watching|watched|reach|reaches|reaching|reached|add|adds|adding|added|produce|produces|producing|produced|provide|provides|providing|provided|pick|picks|picking|picked|wear|wears|wearing|wore|worn|open|opens|opening|opened|win|wins|winning|won|catch|catches|catching|caught|pass|passes|passing|passed|shake|shakes|shaking|shook|shaken|smile|smiles|smiling|smiled|stare|stares|staring|stared|sell|sells|selling|sold|spend|spends|spending|spent|apply|applies|applying|applied|form|forms|forming|formed|obtain|obtains|obtaining|obtained|arrange|arranges|arranging|arranged|beat|beats|beating|beaten|check|checks|checking|checked|cover|covers|covering|covered|divide|divides|dividing|divided|earn|earns|earning|earned|extend|extends|extending|extended|fix|fixes|fixing|fixed|hang|hangs|hanging|hanged|hung|join|joins|joining|joined|lie|lies|lying|lay|lain|lied|obtain|obtains|obtaining|obtained|pull|pulls|pulling|pulled|repeat|repeats|repeating|repeated|receive|receives|receiving|received|save|saves|saving|saved|share|shares|sharing|shared|smile|smiles|smiling|smiled|throw|throws|throwing|threw|thrown|visit|visits|visiting|visited|accompany|accompanies|accompanying|accompanied|acquire|acquires|acquiring|acquired|advance|advances|advancing|advanced|behave|behaves|behaving|behaved|borrow|borrows|borrowing|borrowed|burn|burns|burning|burned|burnt|clean|cleaner|cleanest|cleans|cleaning|cleaned|climb|climbs|climbing|climbed|combine|combines|combining|combined|control|controls|controlling|controlled|defend|defends|defending|defended|deliver|delivers|delivering|delivered|dig|digs|digging|dug|encounter|encounters|encountering|encountered|engage|engages|engaging|engaged|exercise|exercised|exercising|exercises|expand|expands|expanding|expanded|explore|explores|exploring|explored|reduce|reduces|reducing|reduced)";
  
  # Communication verbs 
  # ELF: corrected a typo for "descibe" and added its other forms, removed "spake" as a form of SPEAK, removed some adjective forms like "fitter, fittest", etc.
  # In addition, British spellings and the verbs "AGREE, ASSERT, BEG, CONFIDE, COMMAND, DISAGREE, OBJECT, PLEDGE, PRONOUNCE, PLEAD, REPORT, TESTIFY, VOW" (taken from the public and suasive lists above) were added. "MEAN" which was originally assigned to the mental verb list was added to the communication list, instead.
  $vb_comm = "(say|says|saying|said|tell|tells|telling|told|call|calls|calling|called|ask|asks|asking|asked|write|writes|writing|wrote|written|talk|talks|talking|talked|speak|speaks|spoke|spoken|speaking|thank|thanks|thanking|thanked|describe|describing|describes|described|claim|claims|claiming|claimed|offer|offers|offering|offered|admit|admits|admitting|admitted|announce|announces|announcing|announced|answer|answers|answering|answered|argue|argues|arguing|argued|deny|denies|denying|denied|discuss|discusses|discussing|discussed|encourage|encourages|encouraging|encouraged|explain|explains|explaining|explained|express|expresses|expressing|expressed|insist|insists|insisting|insisted|mention|mentions|mentioning|mentioned|offer|offers|offering|offered|propose|proposes|proposing|proposed|quote|quotes|quoting|quoted|reply|replies|replying|replied|shout|shouts|shouting|shouted|sign|signs|signing|signed|sing|sings|singing|sang|sung|state|states|stating|stated|teach|teaches|teaching|taught|warn|warns|warning|warned|accuse|accuses|accusing|accused|acknowledge|acknowledges|acknowledging|acknowledged|address|addresses|addressing|addressed|advise|advises|advising|advised|appeal|appeals|appealing|appealed|assure|assures|assuring|assured|challenge|challenges|challenging|challenged|complain|complains|complaining|complained|consult|consults|consulting|consulted|convince|convinces|convincing|convinced|declare|declares|declaring|declared|demand|demands|demanding|demanded|emphasize|emphasizes|emphasizing|emphasized|emphasise|emphasises|emphasising|emphasised|excuse|excuses|excusing|excused|inform|informs|informing|informed|invite|invites|inviting|invited|persuade|persuades|persuading|persuaded|phone|phones|phoning|phoned|pray|prays|praying|prayed|promise|promises|promising|promised|question|questions|questioning|questioned|recommend|recommends|recommending|recommended|remark|remarks|remarking|remarked|respond|responds|responding|responded|specify|specifies|specifying|specified|swear|swears|swearing|swore|sworn|threaten|threatens|threatening|threatened|urge|urges|urging|urged|welcome|welcomes|welcoming|welcomed|whisper|whispers|whispering|whispered|suggest|suggests|suggesting|suggested|plead|pleads|pleaded|pleading|agree|agrees|agreed|agreeing|assert|asserts|asserting|asserted|beg|begs|begging|begged|confide|confides|confiding|confided|command|commands|commanding|commanded|disagree|disagreeing|disagrees|disagreed|object|objects|objected|objects|pledge|pledges|pledging|pledged|report|reports|reported|reporting|testify|testifies|testified|testifying|vow|vows|vowing|vowed|mean|means|meaning|meant)";
  
  # Mental verbs
  # ELF: Added British spellings, removed AFFORD and FIND. Removed DESERVE which is also on Biber's (2006) existential list. Added wan to account for wanna tokenised as wan na.
  $vb_mental =	"(see|sees|seeing|saw|seen|know|knows|knowing|knew|known|think|thinks|thinking|thought|want|wan|wants|wanting|wanted|need|needs|needing|needed|feel|feels|feeling|felt|like|likes|liking|liked|hear|hears|hearing|heard|remember|remembers|remembering|remembered|believe|believes|believing|believed|read|reads|reading|consider|considers|considering|considered|suppose|supposes|supposing|supposed|listen|listens|listening|listened|love|loves|loving|loved|wonder|wonders|wondering|wondered|understand|understands|understood|expect|expects|expecting|expected|hope|hopes|hoping|hoped|assume|assumes|assuming|assumed|determine|determines|determining|determined|agree|agrees|agreeing|agreed|bear|bears|bearing|bore|borne|care|cares|caring|cared|choose|chooses|choosing|chose|chosen|compare|compares|comparing|compared|decide|decides|deciding|decided|discover|discovers|discovering|discovered|doubt|doubts|doubting|doubted|enjoy|enjoys|enjoying|enjoyed|examine|examines|examining|examined|face|faces|facing|faced|forget|forgets|forgetting|forgot|forgotten|hate|hates|hating|hated|identify|identifies|identifying|identified|imagine|imagines|imagining|imagined|intend|intends|intending|intended|learn|learns|learning|learned|learnt|miss|misses|missing|missed|mind|minds|minding|notice|notices|noticing|noticed|plan|plans|planning|planned|prefer|prefers|preferring|preferred|prove|proves|proving|proved|proven|realize|realizes|realizing|realized|recall|recalls|recalling|recalled|recognize|recognizes|recognizing|recognized|recognise|recognises|recognising|recognised|regard|regards|regarding|regarded|suffer|suffers|suffering|suffered|wish|wishes|wishing|wished|worry|worries|worrying|worried|accept|accepts|accepting|accepted|appreciate|appreciates|appreciating|appreciated|approve|approves|approving|approved|assess|assesses|assessing|assessed|blame|blames|blaming|blamed|bother|bothers|bothering|bothered|calculate|calculates|calculating|calculated|conclude|concludes|concluding|concluded|celebrate|celebrates|celebrating|celebrated|confirm|confirms|confirming|confirmed|count|counts|counting|counted|dare|dares|daring|dared|detect|detects|detecting|detected|dismiss|dismisses|dismissing|dismissed|distinguish|distinguishes|distinguishing|distinguished|experience|experiences|experiencing|experienced|fear|fears|fearing|feared|forgive|forgives|forgiving|forgave|forgiven|guess|guesses|guessing|guessed|ignore|ignores|ignoring|ignored|impress|impresses|impressing|impressed|interpret|interprets|interpreting|interpreted|judge|judges|judging|judged|justify|justifies|justifying|justified|observe|observes|observing|observed|perceive|perceives|perceiving|perceived|predict|predicts|predicting|predicted|pretend|pretends|pretending|pretended|reckon|reckons|reckoning|reckoned|remind|reminds|reminding|reminded|satisfy|satisfies|satisfying|satisfied|solve|solves|solving|solved|study|studies|studying|studied|suspect|suspects|suspecting|suspected|trust|trusts|trusting|trusted)";
  
  # Facilitation or causation verbs
  $vb_cause = "(help|helps|helping|helped|let|lets|letting|allow|allows|allowing|allowed|affect|affects|affecting|affected|cause|causes|causing|caused|enable|enables|enabling|enabled|ensure|ensures|ensuring|ensured|force|forces|forcing|forced|prevent|prevents|preventing|prevented|assist|assists|assisting|assisted|guarantee|guarantees|guaranteeing|guaranteed|influence|influences|influencing|influenced|permit|permits|permitting|permitted|require|requires|requiring|required)";

  # Occurrence verbs
  $vb_occur = "(become|becomes|becoming|became|happen|happens|happening|happened|change|changes|changing|changed|die|dies|dying|died|grow|grows|grew|grown|growing|develop|develops|developing|developed|arise|arises|arising|arose|arisen|emerge|emerges|emerging|emerged|fall|falls|falling|fell|fallen|increase|increases|increasing|increased|last|lasts|lasting|lasted|rise|rises|rising|rose|risen|disappear|disappears|disappearing|disappeared|flow|flows|flowing|flowed|shine|shines|shining|shone|shined|sink|sinks|sank|sunk|sunken|sinking|slip|slips|slipping|slipped|occur|occurs|occurring|occurred)";

  # Existence or relationship verbs ELF: Does not include the copular BE as in Biber (2006). LOOK was also removed due to too high polysemy. 
  $vb_exist =	"(seem|seems|seeming|seemed|stand|stands|standing|stood|stay|stays|staid|stayed|staying|live|lives|living|lived|appear|appears|appearing|appeared|include|includes|including|included|involve|involves|involving|involved|contain|contains|containing|contained|exist|exists|existing|existed|indicate|indicates|indicating|indicated|concern|concerns|concerning|concerned|constitute|constitutes|constituting|constituted|define|defines|defining|defined|derive|derives|deriving|derived|illustrate|illustrates|illustrating|illustrated|imply|implies|implying|implied|lack|lacks|lacking|lacked|owe|owes|owing|owed|own|owns|owning|owned|possess|possesses|possessing|possessed|suit|suits|suiting|suited|vary|varies|varying|varied|fit|fits|fitting|fitted|matter|matters|mattering|mattered|reflect|reflects|reflecting|reflected|relate|relates|relating|related|remain|remains|remaining|remained|reveal|reveals|revealing|revealed|sound|sounds|sounding|sounded|tend|tends|tending|tended|represent|represents|representing|represented|deserve|deserves|deserving|deserved)";

  # Aspectual verbs
  $vb_aspect =	"(start|starts|starting|started|keep|keeps|keeping|kept|stop|stops|stopping|stopped|begin|begins|beginning|began|begun|complete|completes|completing|completed|end|ends|ending|ended|finish|finishes|finishing|finished|cease|ceases|ceasing|ceased|continue|continues|continuing|continued)";
  
  # Days of the week ELF: Added to include them in normal noun (NN) count rather than NNP (currently not in use)
  #$days = "(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|Mon\.+|Tue\.+|Wed\.+|Thu\.+|Fri\.+|Sat\.+|Sun\.+)";
  
  # Months ELF: Added to include them in normal noun (NN) count rather than NNP (currently not in use)
  #$months = "(January|Jan|February|Feb|March|Mar|April|Apr|May|May|June|Jun|July|Jul|August|Aug|September|Sep|October|Oct|November|Nov|December|Dec)";
  
  # Stative verbs  
  # ELF: This is a new list which was added on DS's suggestion to count JPRED adjectives more accurately. Predicative adjectives are now identified by exclusion (= adjectives not identified as attributive adjectives) but this dictionary remains useful to disambiguate between PASS and PEAS when the auxiliary is "'s".
  $v_stative = "(appear|appears|appeared|feel|feels|feeling|felt|look|looks|looking|looked|become|becomes|became|becoming|get|gets|getting|got|go|goes|going|gone|went|grow|grows|growing|grown|prove|proves|proven|remain|remains|remaining|remained|seem|seems|seemed|shine|shines|shined|shone|smell|smells|smelt|smelled|sound|sounds|sounded|sounding|stay|staying|stayed|stays|taste|tastes|tasted|turn|turns|turning|turned)";
  
  # Function words
  # EFL: Added in order to calculate a content to function word ratio to capture lexical density
  $function_words = "(a|about|above|after|again|ago|ai|all|almost|along|already|also|although|always|am|among|an|and|another|any|anybody|anything|anywhere|are|are|around|as|at|back|be|been|before|being|below|beneath|beside|between|beyond|billion|billionth|both|but|by|can|can|could|cos|cuz|did|do|does|doing|done|down|during|each|eight|eighteen|eighteenth|eighth|eightieth|eighty|either|eleven|eleventh|else|enough|even|ever|every|everybody|everyone|everything|everywhere|except|far|few|fewer|fifteen|fifteenth|fifth|fiftieth|fifty|first|five|for|fortieth|forty|four|fourteen|fourteenth|fourth|from|get|gets|getting|got|had|has|have|having|he|hence|her|here|hers|herself|him|himself|his|hither|how|however|hundred|hundredth|i|if|in|into|is|it|its|itself|just|last|less|many|may|me|might|million|millionth|mine|more|most|much|must|my|myself|near|near|nearby|nearly|neither|never|next|nine|nineteen|nineteenth|ninetieth|ninety|ninth|no|nobody|none|noone|nor|not|nothing|now|nowhere|of|off|often|on|once|one|only|or|other|others|ought|our|ours|ourselves|out|over|quite|rather|round|second|seven|seventeen|seventeenth|seventh|seventieth|seventy|shall|sha|she|should|since|six|sixteen|sixteenth|sixth|sixtieth|sixty|so|some|somebody|someone|something|sometimes|somewhere|soon|still|such|ten|tenth|than|that|that|the|their|theirs|them|themselves|then|thence|there|therefore|these|they|third|thirteen|thirteenth|thirtieth|thirty|this|thither|those|though|thousand|thousandth|three|thrice|through|thus|till|to|today|tomorrow|too|towards|twelfth|twelve|twentieth|twenty|twice|two|under|underneath|unless|until|up|us|very|was|we|were|what|when|whence|where|whereas|which|while|whither|who|whom|whose|why|will|with|within|without|wo|would|yes|yesterday|yet|you|your|yours|yourself|yourselves|'re|'ve|n't|'ll|'twas|'em|y'|b|c|d|e|f|g|h|i|j|k|l|m|n|o|p|q|r|s|t|u|v|w|x|y|z|a|b|c|d|e|f|g|h|i|j|k|l|m|n|o|p|q|r|s|t|u|v|w|x|y|z|1|2|3|4|5|6|7|8|9|0)";
  
  
    # ELF added variable: Emojis :)
    # Should match all official emoji as of Dec 2018 :)
    # Cf. https://unicode.org/emoji/charts-11.0/full-emoji-list.html
    # Cf. https://www.mclean.net.nz/ucf/
    $emoji = "(😀|😁|😂|🤣|😃|😄|😅|😆|😉|😊|😋|😎|😍|😘|🥰|😗|😙|😚|☺|(\u263A)️|🙂|🤗|🤩|🤔|🤨|😐|😑|😶|🙄|😏|😣|😥|😮|🤐|😯|😪|😫|😴|😌|😛|😜|😝|🤤|😒|😓|😔|😕|🙃|🤑|😲|☹️|(\u2639)|🙁|😖|😞|😟|😤|😢|😭|😦|😧|😨|😩|🤯|😬|😰|😱|🥵|🥶|😳|🤪|😵|😡|😠|🤬|😷|🤒|🤕|🤢|🤮|🤧|😇|🤠|🤡|🥳|🥴|🥺|🤥|🤫|🤭|🧐|🤓|😈|👿|👹|👺|💀|👻|👽|🤖|💩|😺|😸|😹|😻|😼|😽|🙀|😿|😾|👶|👧|🧒|👦|👩|🧑|👨|👵|🧓|👴|👲|👳‍️|👳‍️|🧕|🧔|👱‍|👱‍️|👨‍|👩‍|🦸‍️|🦹‍️|👮‍️|👷‍️|💂‍️️|🕵️‍️|👩‍|👨‍|👰|🤵|👸|🤴|🤶|🎅|🧙‍️️|🧝‍️️|🧛‍️️|🧟‍️️|🧞‍️️|🧜‍️️|🧚‍️️|👼|🤰|🤱|🙇‍️️|💁‍️️|🙅‍️|🙆‍️|🙋‍️️|🤦‍️|🤷‍️|🙎‍️️|🙍‍️️|💇‍️️|💆‍️|🧖‍️️|💅|🤳|💃|🕺|👯‍️️|🕴|🚶‍️|🏃‍️|👫|👭|👬|💑|👩‍|👨‍|💏|👪|🤲|👐|🙌|👏|🤝|👍|👎|👊|✊|🤛|🤜|🤞|✌️|(\u270C)|🤟|🤘|👌|👈|👉|👆|👇|☝️|(\u261D)|✋|🤚|🖐|🖖|👋|🤙|💪|🦵|🦶|🖕|✍|(\u270D)|️🙏|💍|💄|💋|👄|👅|👂|👃|👣|👁|👀|🧠|🦴|🦷|🗣|👤|👥|🧥|👚|👕|👖|👔|👗|👙|👘|👠|👡|👢|👞|👟|🥾|🥿|🧦|🧤|🧣|🎩|🧢|👒|🎓|⛑|👑|👝|👛|👜|💼|🎒|👓|🕶|🥽|🥼|🌂|🧵|🧶|👶|👦|🐶|🐱|🐭|🐹|🐰|🦊|🦝|🐻|🐼|🦘|🦡|🐨|🐯|🦁|🐮|🐷|🐽|🐸|🐵|🙈|🙉|🙊|🐒|🐔|🐧|🐦|🐤|🐣|🐥|🦆|🦢|🦅|🦉|🦚|🦜|🦇|🐺|🐗|🐴|🦄|🐝|🐛|🦋|🐌|🐚|🐞|🐜|🦗|🕷|🕸|🦂|🦟|🦠|🐢|🐍|🦎|🦖|🦕|🐙|🦑|🦐|🦀|🐡|🐠|🐟|🐬|🐳|🐋|🦈|🐊|🐅|🐆|🦓|🦍|🐘|🦏|🦛|🐪|🐫|🦙|🦒|🐃|🐂|🐄|🐎|🐖|🐏|🐑|🐐|🦌|🐕|🐩|🐈|🐓|🦃|🕊|🐇|🐁|🐀|🐿|🦔|🐾|🐉|🐲|🌵|🎄|🌲|🌳|🌴|🌱|🌿|☘️|🍀|🎍|🎋|🍃|🍂|🍁|🍄|🌾|💐|🌷|🌹|🥀|🌺|🌸|🌼|🌻|🌞|🌝|🌛|🌜|🌚|🌕|🌖|🌗|🌘|🌑|🌒|🌓|🌔|🌙|🌎|🌍|🌏|💫|⭐|(\u2606)️️|🌟|✨|⚡️|☄️|(\u2604)|💥|🔥|🌪|🌈|☀️|(\u2734)|🌤|⛅️|🌥|☁️|🌦|🌧|⛈|🌩|🌨|❄️|(\u2744)|☃|(\u2603)️|⛄️|🌬|💨|💧|💦|☔️|☂️|🌊|🌫|🍏|🍎|🍐|🍊|🍋|🍌|🍉|🍇|🍓|🍈|🍒|🍑|🍍|🥭|🥥|🥝|🍅|🍆|🥑|🥦|🥒|🥬|🌶|🌽|🥕|🥔|🍠|🥐|🍞|🥖|🥨|🥯|🧀|🥚|🍳|🥞|🥓|🥩|🍗|🍖|🌭|🍔|🍟|🍕|🥪|🥙|🌮|🌯|🥗|🥘|🥫|🍝|🍜|🍲|🍛|🍣|🍱|🥟|🍤|🍙|🍚|🍘|🍥|🥮|🥠|🍢|🍡|🍧|🍨|🍦|🥧|🍰|🎂|🍮|🍭|🍬|🍫|🍿|🧂|🍩|🍪|🌰|🥜|🍯|🥛|🍼|☕️|🍵|🥤|🍶|🍺|🍻|🥂|🍷|🥃|🍸|🍹|🍾|🥄|🍴|🍽|🥣|🥡|🥢|⚽️|🏀|🏈|⚾️|🥎|🏐|🏉|🎾|🥏|🎱|🏓|🏸|🥅|🏒|🏑|🥍|🏏|⛳️|🏹|🎣|🥊|🥋|🎽|⛸|🥌|🛷|🛹|🎿|⛷|🏂|🏋️‍|🤼‍|🤸‍️|⛹️‍|🤺|🤾‍️|🏌️‍️|🏇|🧘‍️|🏄‍️|🏊‍️|🤽‍️|🚣‍|🧗‍️|🚵‍|🚴|🏆|🥇|🥈|🥉|🏅|🎖|🏵|🎗|🎫|🎟|🎪|🤹‍️|🤹|🎭|🎨|🎬|🎤|🎧|🎼|🎹|🥁|🎷|🎺|🎸|🎻|🎲|🧩|♟|🎯|🎳|🎮|🎰|🚗|🚕|🚙|🚌|🚎|🏎|🚓|🚑|🚒|🚐|🚚|🚛|🚜|🛴|🚲|🛵|🏍|🚨|🚔|🚍|🚘|🚖|🚡|🚠|🚟|🚃|🚋|🚞|🚝|🚄|🚅|🚈|🚂|🚆|🚇|🚊|🚉|✈️|🛫|🛬|🛩|💺|🛰|🚀|🛸|🚁|🛶|⛵️|🚤|🛥|🛳|⛴|🚢|⚓️|⛽️|🚧|🚦|🚥|🚏|🗺|🗿|🗽|🗼|🏰|🏯|🏟|🎡|🎢|🎠|⛲️|⛱|🏖|🏝|🏜|🌋|⛰|🏔|🗻|🏕|⛺️|🏠|🏡|🏘|🏚|🏗|🏭|🏢|🏬|🏣|🏤|🏥|🏦|🏨|🏪|🏫|🏩|💒|🏛|⛪️|🕌|🕍|🕋|⛩|🛤|🛣|🗾|🎑|🏞|🌅|🌄|🌠|🎇|🎆|🌇|🌆|🏙|🌃|🌌|🌉|🌁|🆓|📗|📕|⌚️|📱|📲|💻|⌨️|🖥|🖨|🖱|🖲|🕹|🗜|💽|💾|💿|📀|📼|📷|📸|📹|🎥|📽|🎞|📞|☎️|📟|📠|📺|📻|🎙|🎚|🎛|⏱|⏲|⏰|🕰|⌛️|⏳|📡|🔋|🔌|💡|🔦|🕯|🗑|🛢|💸|💵|💴|💶|💷|💰|💳|🧾|💎|⚖️|(\u2696)|🔧|🔨|⚒|(\u2692)|🛠|⛏|🔩|⚙️|⛓|🔫|💣|🔪|🗡|⚔|(\u2694)️|🛡|🚬|⚰️|(\u26B0)|⚱️|🏺|🧭|🧱|🔮|🧿|🧸|📿|💈|⚗️|🔭|🧰|🧲|🧪|🧫|🧬|🧯|🔬|🕳|💊|💉|🌡|🚽|🚰|🚿|🛁|🛀|🛀🏻|🛀🏼|🛀🏽|🛀🏾|🛀🏿|🧴|🧵|🧶|🧷|🧹|🧺|🧻|🧼|🧽|🛎|🔑|🗝|🚪|🛋|🛏|🛌|🖼|🛍|🧳|🛒|🎁|🎈|🎏|🎀|🎊|🎉|🧨|🎎|🏮|🎐|🧧|✉️|📩|📨|📧|💌|📥|📤|📦|🏷|📪|📫|📬|📭|📮|📯|📜|📃|📄|📑|📊|📈|📉|🗒|🗓|📆|📅|📇|🗃|🗳|🗄|📋|📁|📂|🗂|🗞|📰|📓|📔|📒|📕|📗|📘|📙|📚|📖|🔖|🔗|📎|🖇|📐|📏|📌|📍|✂️|🖊|🖋|✒️|🖌|🖍|📝|✏|(\u270F)️|🔍|🔎|🔏|🔐|🔒|🔓|❤|(\u2665)️|🧡|💛|💚|💙|💜|🖤|💔|❣️|💕|💞|💓|💗|💖|💘|💝|💟|☮️|✝️|☪️|🕉|☸️|✡️|🔯|🕎|☯️|☦️|🛐|⛎|♈️|♉️|♊️|♋️|♌️|♍️|♎️|♏️|♐️|♑️|♒️|♓️|🆔|⚛️|🉑|☢️|☣️|📴|📳|🈶|🈚️|🈸|🈺|🈷️|✴️|🆚|💮|🉐|㊙️|㊗️|🈴|🈵|🈹|🈲|🅰️|🅱️|🆎|🆑|🅾️|🆘|❌|⭕️|🛑|⛔️|📛|🚫|💯|💢|♨️|🚷|🚯|🚳|🚱|🔞|📵|🚭|❗️|❕|❓|❔|‼️|⁉️|🔅|🔆|〽️|⚠️|(\u26A0)|🚸|🔱|⚜️|🔰|♻️|✅|🈯️|💹|❇️|✳️|❎|🌐|💠|Ⓜ️|🌀|💤|🏧|🚾|♿️|🅿️|🈳|🈂️|🛂|🛃|🛄|🛅|🚹|🚺|🚼|🚻|🚮|🎦|📶|🈁|🔣|ℹ️|🔤|🔡|🔠|🆖|🆗|🆙|🆒|🆕|🆓|0️⃣|1️⃣|2️⃣|3️⃣|4️⃣|5️⃣|6️⃣|7️⃣|8️⃣|9️⃣|🔟|🔢|#️⃣|⏏️|▶️|⏸|⏯|⏹|⏺|⏭|⏮|⏩|⏪|⏫|⏬|◀️|🔼|🔽|➡️|⬅️|⬆️|⬇️|↗️|↘️|↙️|↖️|↕️|↔️|↪️|↩️|⤴️|⤵️|🔀|🔁|🔂|🔄|🔃|🎵|🎶|➕|➖|➗|✖️|♾|💲|💱|™️|©️|®️|〰️|➰|➿|🔚|🔙|🔛|🔝|🔜|✔️|☑|(\u2611)️|🔘|⚪️|⚫️|🔴|🔵|🔺|🔻|🔸|🔹|🔶|🔷|🔳|🔲|▪️|▫️|◾️|◽️|◼️|◻️|⬛️|⬜️|🔈|🔇|🔉|🔊|🔔|🔕|📣|📢|👁‍🗨|💬|💭|🗯|♠️|♣️|♥️|♦️|(\u2660)|(\u2661)|(\u2662)|(\u2663)|(\u2664)|(\u2666)|(\u2667)|🃏|🎴|🀄️|🕐|🕑|🕒|🕓|🕔|🕕|🕖|🕗|🕘|🕙|🕚|🕛|🕜|🕝|🕞|🕟|🕠|🕡|🕢|🕣|🕤|🕥|🕦|🕧|🏳️|🏴|🏁|🚩|🏳️‍|🌈|🏴|‍☠️|🎌|🥰|🥵|🥶|🥳|🥴|🥺|👨‍🦰|👩‍🦰|👨‍🦱|👩‍🦱|👨‍🦲|👩‍🦲|👨‍🦳|👩‍🦳|🦸️|🦹️|🦵|🦶|🦴|🦷|🥽|🥼|🥾|🥿|🦝|🦙|🦛|🦘|🦡|🦢|🦚|🦜|🦞|🦟|🦠|🥭|🥬|🥯|🧂|🥮|🧁|🧭|🧱|🛹|🧳|🧨|🧧|🥎|🥏|🥍|🧿|🧩|🧸|♟|🧮|🧾|🧰|🧲|🧪|🧫|🧬|🧯|🧴|🧵|🧶|🧷|🧹|🧺|🧻|🧼|🧽|♾|🏴‍|☠)"; 

  
      #--------------------------------------------------

# QUICK CORRECTIONS OF STANFORD TAGGER OUTPUT

  foreach $x (@word) {

    # Changes the two tags that have a problematic "$" symbol in the Stanford tagset
    if ($x =~ /PRP\$/) { $x =~ s/PRP./PRPS/; }
    if ($x =~ /WP\$/) { $x =~ s/WP./WPS/; }
  
  	# ELF: Correction of a few specific symbols identified as adjectives, cardinal numbers and foreign words by the Stanford Tagger.
  	# These are instead re-tagged as symbols so they don't count as tokens for the TTR and per-word normalisation basis.
  	# Removal of all LS (list symbol) tags except those that denote numbers
  	if ($x =~ /<_JJ|>_JJ|\^_FW|>_JJ|§_CD|=_JJ|\*_|\W+_LS|[a-zA-Z]+_LS/) { 
  		$x =~ s/_\w+/_SYM/; 
  		}
  		
  		
  	# ELF: Correction of cardinal numbers without spaces and list numbers as numbers rather than LS
  	# Removal of the LS (list symbol) tags that denote numbers
  	if ($x =~ /\b[0-9]+th_|\b[0-9]+nd_|\b[0-9]+rd_|[0-9]+_LS/) { 
  		$x =~ s/_\w+/_CD/; 
  		}  		

  	# ELF: Correct "innit" and "init" (frequently tagged as a noun by the Stanford Tagger) to pronoun "it" (these are later on also counted as question tags if they are followed by a question mark)
  	if ($x =~ /\binnit_/) { $x =~ s/_\w+/_PIT/; }
  	if ($x =~ /\binit_/) { $x =~ s/_\w+/_PIT/; }	

    
  # ADDITIONAL TAGS FOR INTERNET REGISTERS
    
  	# ELF: Tagging of emoji
  	if ($x =~ /($emoji)/) {
  		$x =~ s/_\w+/_EMO/;
    }
    
 	 # ELF: Tagging of hashtags
  	if ($x =~ /#\w{3,}/) {
  		$x =~ s/_\w+/_HST/;
    }
    
 	 # ELF: Tagging of web links
 	 # Note that the aim of this regex is *not* to extract all *valid* URLs but rather all strings that were intended to be a URL or a URL-like string!
 	 # Inspired by: https://mathiasbynens.be/demo/url-regex
  	if (($x =~ /\b(https?:\/\/www\.|https?:\/\/)?\w+([\-\.]{1}\w+)*\.[a-z]{2,5}(:[0-9]{1,5})?(\/.*)?\b/i) ||
  		($x =~ /<link\/?>/) ||
  		($x =~ /\b\w+\.(com|net|co\.uk|au|us|gov|org)\b/)) {
  		$x =~ s/_\w+/_URL/;
    }
    
  # BASIC TAG NEEDED FOR MORE COMPLEX TAGS
    # Negation
    if ($x =~ /\bnot_|\bn't_/i) {
      $x =~ s/_\w+/_XX0/;
    }
    
  }

# SLIGHTLY MORE COMPLEX CORRECTIONS OF STANFORD TAGGER OUTPUT

	# CORRECTION OF "TO" AS PREPOSITION 
	# ELF: Added "to" followed by a punctuation mark, e.g. "What are you up to?"
  
  	for ($j=0; $j<@word; $j++) {
  	
  	# Adding the most frequent emoticons to the emoji list
  	# Original list: https://repository.upenn.edu/pwpl/vol18/iss2/14/
  	# Plus crowdsourced other emoticons from colleagues on Twitter ;-)
  	
  	# For emoticons parsed as one token by the Stanford Tagger:
  	# The following were removed because they occur fairly frequently in academic writing ;-RRB-_ and -RRB-:_
  	if ($word[$j] =~ /\b(:-RRB-_|:d_|:-LRB-_|:p_|:--RRB-_|:-RSB-_|\bd:_|:'-LRB-_|:--LRB-_|:-d_|:-LSB-_|-LSB-:_|:-p_|:\/_|:P_|:D_|\b=-RRB-_|\b=-LRB-_|:-D_|:-RRB--RRB-_|:O_|:]_|:-LRB--LRB-_|:o_|:-O_|:-o_|;--RRB-_|;-\*|‘:--RRB--LRB-_|:-B_|\b8--RRB-_|=\|_|:-\|_|\b<3_|\bOo_|\b<\/3_|:P_|;P_|\bOrz_|\borz_|\bXD_|\bxD_|\bUwU_)/) {
        $word[$j] =~ s/_\w+/_EMO/;
  	}
  	
  	# For emoticons where each character is parsed as an individual token.
  	# The aim here is to only have one EMO tag per emoticon and, if there are any letters in the emoticon, for the EMO tag to be placed on the letter to overwrite any erroneous NN, FW or LS tags from the Stanford Tagger:
    if (($word[$j] =~ /:_\W+|;_\W+|=_/ && $word[$j+1] =~ /\/_\W+|\b\\_\W+/) ||
    	#($word[$j] =~ /:_|;_|=_/ && $word[$j+1] =~ /-LRB-|-RRB-|-RSB-|-LSB-/) || # This line can be used to improve recall when tagging internet registers with lots of emoticons but is not recommended for a broad range of registers since it will cause a serious drop in precision in registers with a lot of punctuation, e.g., academic English.
   		($word[$j] =~ /\bd_|\bp_/i && $word[$j+1] =~ /\b:_/) ||
   		($word[$j] =~ /:_\W+|;_\W+|\b8_/ && $word[$j+1] =~ /\b-_|'_|-LRB-|-RRB-/ && $word[$j+2] =~ /-LRB-|-RRB-|\b\_|\b\/_|\*_/)) {
        $word[$j] =~ s/_\w+/_EMO/;
        $word[$j] =~ s/_(\W+)/_EMO/;
    }  
      
  	# For other emoticons where each character is parsed as an individual token and the letters occur in +1 position.
  	
    if (($word[$j] =~ /<_/ && $word[$j+1] =~ /\b3_/) ||
    	#($word[$j] =~ /:_|;_|=_/ && $word[$j+1] =~ /\bd_|\bp_|\bo_|\b3_/i) || # # These two lines may be used to improve recall when tagging internet registers with lots of emoticons but is not recommended for a broad range of registers since it will cause a serious drop in precision in registers with a lot of punctuation, e.g., academic English.
   		#($word[$j] =~ /-LRB-|-RRB-|-RSB-|-LSB-/ && $word[$j+1] =~ /:_|;_/) || 
   		($word[$j-1] =~ />_/ && $word[$j] =~ /:_/ && $word[$j+1] =~ /-LRB-|-RRB-|\bD_/) ||
   		($word[$j] =~ /\^_/ && $word[$j+1] =~ /\^_/) ||
   		($word[$j] =~ /:_\W+/ && $word[$j+1] =~ /\bo_|\b-_/i && $word[$j+2] =~ /-LRB-|-RRB-/) ||
   		($word[$j-1] =~ /<_/ && $word[$j] =~ /\/_/ && $word[$j+1] =~ /\b3_/) ||
   		($word[$j-1] =~ /:_\W+|\b8_|;_\W+|=_/ && $word[$j] =~ /\b-_|'_|-LRB-|-RRB-/ && $word[$j+1] =~ /\bd_|\bp_|\bo_|\bb_|\b\|_|\b\/_/i && $word[$j+2] !~ /-RRB-/)) {
        $word[$j+1] =~ s/_\w+/_EMO/;
        $word[$j+1] =~ s/_(\W+)/_EMO/;
    }    
    
    # Correct double punctuation such as ?! and !? (often tagged by the Stanford Tagger as a noun or foreign word) 
    if ($word[$j] =~ /[\?\!]{2,15}/) {
     		 $word[$j] =~ s/_(\W+)/_\./;
     		 $word[$j] =~ s/_(\w+)/_\./;
    }
    
    if ($word[$j] =~ /\bto_/i && $word[$j+1] =~ /_IN|_CD|_DT|_JJ|_WPS|_NN|_NNP|_PDT|_PRP|_WDT|(\b($wp))|_WRB|_\W/i) {
     	 $word[$j] =~ s/_\w+/_IN/;
    }
    
    # ELF: correcting "I dunno"
    if ($word[$j] =~ /\bdu_/i && $word[$j+1] =~ /\bn_/ && $word[$j+2] =~ /\bno_/) { 
    	$word[$j] =~ s/_\w+/_VPRT/;
    	$word[$j+1] =~ s/_\w+/_XX0/;
    	$word[$j+2] =~ s/_\w+/_VB/;
    }
    
    if ($word[$j] =~ /\bhave_VB/i && $word[$j+1] =~ /_PRP/ && $word[$j+2] =~ /_VBN|_VBD/) {
    	$word[$j] =~ s/_\w+/_VPRT/;
    }

	# ELF: Correction of falsely tagged "'s" following "there". 
    
    if ($word[$j-1] =~ /\bthere_EX/i && $word[$j] =~ /_POS/) {
      $word[$j] =~ s/_\w+/_VPRT/;
    }
    
    # ELF: Correction of most problematic spoken language particles
    # ELF: DMA is a new variable. It is important for it to be high up because lots of DMA's are marked as nouns by the Stanford Tagger which messes up other variables further down the line otherwise. More complex DMAs are further down.
    if ($word[$j] =~ /\bactually_|\banyway|\bdamn_|\bgoodness_|\bgosh_|\byeah_|\byep_|\byes_|\bnope_|\bright_UH|\bwhatever_|\bdamn_RB|\blol_|\bIMO_|\bomg_|\bwtf_/i) {
      $word[$j] =~ s/_\w+/_DMA/;
    }

    # ELF: FPUH is a new variable.
    # ELF: tags interjections and filled pauses.
    if ($word[$j] =~ /\baw+_|\bow_|\boh+_|\beh+_|\ber+_|\berm+_|\bmm+_|\bum+_|\b[hu]{2,}_|\bmhm+|\bhi+_|\bhey+_|\bby+e+_|\b[ha]{2,}_|\b[he]{2,}_|\b[wo]{3,}p?s*_|\b[oi]{2,}_|\bouch_/i) {
      $word[$j] =~ s/_(\w+)/_FPUH/;
    }
    # Also added "hm+" on Peter's suggestion but made sure that this was case sensitive to avoid mistagging Her Majesty ;-)
    if ($word[$j] =~ /\bhm+|\bHm+/) {
      $word[$j] =~ s/_(\w+)/_FPUH/;
    }  
    
    #--------------------------------------------------
    
      
# ELF: Added a new variable for "so" as tagged as a preposition (IN) or adverb (RB) by the Stanford Tagger because it most often does not seem to be a preposition/conjunct (but rather a filler, amplifier, etc.) and should therefore not be added to the preposition count.
  
    if ($word[$j] =~ /\bso_IN|\bso_RB/i) {
      $word[$j] =~ s/_\w+/_SO/;
    }
    
# Tags quantifiers 
# ELF: Note that his variable is used to identify several other features. 
# ELF: added "any", "lots", "loada" and "a lot of" and gave it its own loop because it is now more complex and must be completed before the next set of for-loops. Also added "most" except when later overwritten as an EMPH.
# ELF: Added "more" and "less" when tagged by the Stanford Tagger as adjectives (JJ.*). As adverbs (RB), they are tagged as amplifiers (AMP) and downtoners (DWT) respectively.
# ELF: Also added "load(s) of" and "heaps of" on DS's recommendation

      
    # ELF: Getting rid of the Stanford Tagger predeterminer (PDT) category and now counting all those as quantifiers (QUAN)
    if (($word[$j] =~ /_PDT/i) || 
    ($word[$j] =~ /\ball_|\bany_|\bboth_|\beach_|\bevery_|\bfew_|\bhalf_|\bmany_|\bmore_JJ|\bmuch_|\bplenty_|\bseveral_|\bsome_|\blots_|\bloads_|\bheaps_|\bless_JJ|\bloada_|\bwee_/i)||
    
    ($word[$j] =~ /\bload_/i && $word[$j+1] =~ /\bof_/i) ||
    ($word[$j] =~ /\bmost_/i && $word[$j+1] =~ /\bof_|\W+/i) ||
    ($word[$j-1] =~ /\ba_/i && $word[$j] =~ /\blot_|\bbit_/i)) { # ELF: Added "a lot (of)" and removed NULL tags
        $word[$j] =~ s/_\w+/_QUAN/;

  	}
  }
  
  #---------------------------------------------------

  # COMPLEX TAGS
  for ($j=0; $j<@word; $j++) {

  #---------------------------------------------------
 
  # ELF: New variable. Tags the remaining pragmatic and discourse markers 
  # The starting point was Stenström's (1994:59) list of "interactional signals and discourse markers" (cited in Aijmer 2002: 2) 
  # --> but it does not include "now" (since it's already a time adverbial), "please" (included in politeness), "quite" or "sort of" (hedges). 
  # I also added: "nope", "I guess", "mind you", "whatever" and "damn" (if not a verb and not already tagged as an emphatic).
    
    if (($word[$j] =~ /\bno_/i && $word[$j] !~ /_VB/ && $word[$j+1] !~ /_J|_NN/) || # This avoid a conflict with the synthetic negation variable and leaves the "no" in "I dunno" as a present tense verb form and "no" from "no one".
      ($word[$j-1] =~ /_\W|FPUH_/ && $word[$j] =~ /\bright_|\bokay_|\bok_/i) || # Right and okay immediately proceeded by a punctuation mark or a filler word
      ($word[$j-1] !~ /\bas_|\bhow_|\bvery_|\breally_|\bso_|\bquite_|_V/i && $word[$j] =~ /\bwell_JJ|\bwell_RB|\bwell_NNP|\bwell_UH/i && $word[$j+1] !~ /_JJ|_RB/) || # Includes all forms of "well" except as a singular noun assuming that the others are mistags of DMA well's by the Stanford Tagger.
      ($word[$j-1] !~ /\bmakes_|\bmake_|\bmade_|\bmaking_|\bnot|_\bfor_|\byou_|\b($be)/i && $word[$j] =~ /\bsure_JJ|\bsure_RB/i) || # This excludes MAKE sure, BE sure, not sure, and for sure
		($word[$j-1] =~ /\bof_/i && $word[$j] =~ /\bcourse_/i) ||
    	($word[$j-1] =~ /\ball_/i && $word[$j] =~ /\bright_/i) ||
    	($word[$j] =~ /\bmind_/i && $word[$j+1] =~ /\byou_/i)) { 
     
      $word[$j] =~ s/_\w+/_DMA/;
    }
      
    #--------------------------------------------------

    # Tags predicative adjectives 
    # ELF: added list of stative verbs other than BE. Also the last two if-statements to account for lists of adjectives separated by commas and Oxford commas before "and" at the end of a list. Removed the bit about not preceding an adverb.
    
   # if (($word[$j-1] =~ /\b($be)|\b($v_stative)_V/i && $word[$j] =~ /_JJ|\bok_|\bokay_/i && $word[$j+1] !~ /_JJ|_NN/) || # I'm hungry
    #	($word[$j-2] =~ /\b($be)|\b($v_stative)_V/i && $word[$j-1] =~ /_RB|\bso_|_EMPH|_XX0/i && $word[$j] =~ /_JJ|\bok_|\bokay_/i && $word[$j+1] !~ /_JJ|_NN/) || # I'm so|not hungry
    #	($word[$j] =~ /_JJ|ok_|okay_/i && $word[$j+1] =~ /_\./) || # Amazing! Oh nice.
    #	($word[$j-3] =~ /\b($be)|\b($v_stative)_V/i && $word[$j-1] =~ /_XX0|_RB|_EMPH/ && $word[$j] =~ /_JJ/ && $word[$j+1] !~ /_JJ|_NN/)) # I'm just not hungry
    #	{
     #   $word[$j] =~ s/_\w+/_JPRED/;
    #}
  #  if (($word[$j-2] =~ /_JPRED/ && $word[$j-1] =~ /\band_/i && $word[$j] =~ /_JJ/) ||
   # 	($word[$j-2] =~ /_JPRED/ && $word[$j-1] =~ /,_,/ && $word[$j] =~ /_JJ/) ||
    #	($word[$j-3] =~ /_JPRED/ && $word[$j-2] =~ /,_,/ && $word[$j-1] =~ /\band_/ && $word[$j] =~ /_JJ/)) {
     #   $word[$j] =~ s/_\w+/_JPRED/;
    #}
    
    #--------------------------------------------------

    # Tags attribute adjectives (JJAT) (see additional loop further down the line for additional JJAT cases that rely on these JJAT tags)

    if (($word[$j] =~ /_JJ/ && $word[$j+1] =~ /_JJ|_NN|_CD/) ||
		($word[$j-1] =~ /_DT/ && $word[$j] =~ /_JJ/)) {
        $word[$j] =~ s/_\w+/_JJAT/;
    }
    
    # Manually add okay as a predicative adjective (JJPR) because "okay" and "ok" are often tagged as foreign words by the Stanford Tagger. All other predicative adjectives are tagged at the very end.
    
    if ($word[$j-1] =~ /\b($be)/i && $word[$j] =~ /\bok_|okay_/i) {
        $word[$j] =~ s/_\w+/_JJPR/;
    }

    #---------------------------------------------------
   
    # Tags elaborating conjunctions (ELAB)
    # ELF: This is a new variable.
    
    # ELF: added the exception that "that" should not be a determiner. Also added "in that" and "to the extent that" on DS's advice.  
    
    if (($word[$j-1] =~ /\bsuch_/i && $word[$j] =~ /\bthat_/ && $word[$j] !~ /_DT/) ||
      ($word[$j-1] =~ /\bsuch_|\binasmuch__|\bforasmuch_|\binsofar_|\binsomuch/i && $word[$j] =~ /\bas_/) ||
      ($word[$j-1] =~ /\bin_IN/i && $word[$j] =~ /\bthat_/ && $word[$j] !~ /_DT/) ||
      ($word[$j-3] =~ /\bto_/i && $word[$j-2] =~ /\bthe_/ && $word[$j-1] =~ /\bextent_/ && $word[$j] =~ /\bthat_/) ||
      ($word[$j-1] =~ /\bin_/i && $word[$j] =~ /\bparticular_|\bconclusion_|\bsum_|\bsummary_|\bfact_|\bbrief_/i) ||
      ($word[$j-1] =~ /\bto_/i && $word[$j] =~ /\bsummarise_|\bsummarize_/i && $word[$j] =~ /,_/) ||
      ($word[$j-1] =~ /\bfor_/i && $word[$j] =~ /\bexample_|\binstance_/i) ||
      ($word[$j] =~ /\bsimilarly_|\baccordingly_/i && $word[$j+1] =~ /,_/) ||
      ($word[$j-2] =~ /\bin_/i && $word[$j-1] =~ /\bany_/i && $word[$j] =~ /\bevent_|\bcase_/i) ||
      ($word[$j-2] =~ /\bin_/i && $word[$j-1] =~ /\bother_/i && $word[$j] =~ /\bwords_/)) {
        $word[$j] =~ s/_(\w+)/_$1 ELAB/;
    }
    
    if ($word[$j] =~ /\beg_|\be\.g\._|etc\.?_|\bi\.e\._|\bcf\.?_|\blikewise_|\bnamely_|\bviz\.?_/i) {
        $word[$j] =~ s/_\w+/_ELAB/;
    }
    

    #---------------------------------------------------
   
    # Tags coordinating conjunctions (CC)
    # ELF: This is a new variable.
    # ELF: added as well as, as well, in fact, accordingly, thereby, also, by contrast, besides, further_RB, in comparison, instead (not followed by "of").

    if (($word[$j] =~ /\bwhile_IN|\bwhile_RB|\bwhilst_|\bwhereupon_|\bwhereas_|\bwhereby_|\bthereby_|\balso_|\bbesides_|\bfurther_RB|\binstead_|\bmoreover_|\bfurthermore_|\badditionally_|\bhowever_|\binstead_|\bibid\._|\bibid_|\bconversly_/i) || 
      ($word[$j] =~ /\binasmuch__|\bforasmuch_|\binsofar_|\binsomuch/i && $word[$j+1] =~ /\bas_/i) ||
      ($word[$j-1] =~ /_\W/i && $word[$j] =~ /\bhowever_/i) ||
      ($word[$j+1] =~ /_\W/i && $word[$j] =~ /\bhowever_/i) ||
      ($word[$j-1] =~ /\bor_/i && $word[$j] =~ /\brather_/i) ||
      ($word[$j-1] !~ /\bleast_/i && $word[$j] =~ /\bas_/i && $word[$j+1] =~ /\bwell_/i) || # Excludes "as least as well" but includes "as well as"
      ($word[$j-1] =~ /_\W/ && $word[$j] =~ /\belse_|\baltogether_|\brather_/i)) {
        $word[$j] =~ s/_\w+/_CC/;
    }
    
    if (($word[$j-1] =~ /\bby_/i && $word[$j] =~ /\bcontrast_|\bcomparison_/i) ||
      ($word[$j-1] =~ /\bin_/i && $word[$j] =~ /\bcomparison_|\bcontrast_|\baddition_/i) ||
      ($word[$j-2] =~ /\bon_/i && $word[$j-1] =~ /\bthe_/ && $word[$j] =~ /\bcontrary_/i) ||
      ($word[$j-3] =~ /\bon_/i && $word[$j-2] =~ /\bthe_/ && $word[$j-1] =~ /\bone_|\bother_/i && $word[$j] =~ /\bhand_/i)) {
        $word[$j] =~ s/_(\w+)/_$1 CC/;
    }

    #---------------------------------------------------
    
    # Tags causal conjunctions     
    # ELF added: cos, cus, coz, cuz and 'cause (a form spotted in one textbook of the TEC!) plus all the complex forms below.
    
    if (($word[$j] =~ /\bbecause_|\bcos_|\bcos\._|\bcus_|\bcuz_|\bcoz_|\b'cause_/i) ||
    	($word[$j] =~ /\bthanks_/i && $word[$j+1] =~ /\bto_/i) ||
        ($word[$j] =~ /\bthus_/i && $word[$j+1] !~ /\bfar_/i)) {
        $word[$j] =~ s/_\w+/_CUZ/;
    	}
    	
    if (($word[$j-1] =~ /\bin_/i && $word[$j] =~ /\bconsequence_/i) ||
    	($word[$j] =~ /\bconsequently_|\bhence_|\btherefore_/i) ||
    	($word[$j-1] =~ /\bsuch_|\bso_/i && $word[$j] =~ /\bthat_/ && $word[$j] !~ /_DT/) ||
    	($word[$j-2] =~ /\bas_/i && $word[$j-1] =~ /\ba_/i && $word[$j] =~ /\bresult_|\bconsequence_/i) ||
    	($word[$j-2] =~ /\bon_/i && $word[$j-1] =~ /\baccount_/i && $word[$j] =~ /\bof_/i) ||
    	($word[$j-2] =~ /\bfor_/i && $word[$j-1] =~ /\bthat_|\bthis_/i && $word[$j] =~ /\bpurpose_/i) ||
    	($word[$j-2] =~ /\bto_/i && $word[$j-1] =~ /\bthat_|\bthis_/i && $word[$j] =~ /\bend_/i)) {
        	$word[$j] =~ s/_(\w+)/_$1 CUZ/;
    	}

    #---------------------------------------------------

    # Tags conditional conjunctions
    # ELF: added "lest" on DS's suggestion. Added "whether" on PU's suggestion.
    	
	if ($word[$j] =~ /\bif_|\bunless_|\blest_|\botherwise_|\bwhether_/i) {
        	$word[$j] =~ s/_\w+/_COND/;
		}
		
	if (($word[$j-2] =~ /\bas_/i && $word[$j-1] =~ /\blong_/ && $word[$j] =~ /\bas_/) ||
		($word[$j-2] =~ /\bin_/i && $word[$j-1] =~ /\bthat_/ && $word[$j] =~ /\bcase_/)) {
        $word[$j] =~ s/_(\w+)/_$1 COND/;
    	}

    #---------------------------------------------------

    # Tags emphatics 
    # ELF: added "such an" and ensured that the indefinite articles in "such a/an" are not tagged as NULL as was the case in Nini's script. Removed "more".
    # Added: so many, so much, so little, so + VERB, damn + ADJ, least, bloody, fuck, fucking, damn, super and dead + ADJ.
    # Added a differentiation between "most" as as QUAN ("most of") and EMPH.
    # Improved the accuracy of DO + verb by specifying a base form (_VB) so as to avoid: "Did they do_EMPH stuffed_VBN crust?".
    if (($word[$j] =~ /\bmost_DT/i) ||
    	($word[$j] =~ /\breal__|\bdead_|\bdamn_/i && $word[$j+1] =~ /_J/) ||
    	($word[$j-1] =~ /\bat_|\bthe_/i && $word[$j] =~ /\bleast_|\bmost_/) ||
    	($word[$j] =~ /\bso_/i && $word[$j+1] =~ /_J|\bmany_|\bmuch_|\blittle_|_RB/i) ||
      	($word[$j] =~ /\bfar_/i && $word[$j+1] =~ /_J|_RB/ && $word[$j-1] !~ /\bso_|\bthus_/i) ||
      	($word[$j-1] !~ /\bof_/i && $word[$j] =~ /\bsuch_/i && $word[$j+1] =~ /\ba_|\ban_/i)) {
        	$word[$j] =~ s/_\w+/_EMPH/;
    	}
    
    if (($word[$j] =~ /\bloads_/i && $word[$j+1] !~ /\bof_/i) ||
      	($word[$j] =~ /\b($do)/i && $word[$j+1] =~ /_VB\b/) ||
    	($word[$j] =~ /\bjust_|\bbest_|\breally_|\bmost_JJ|\bmost_RB|\bbloody_|\bfucking_|\bfuck_|\bshit_|\bsuper_/i) ||
    	($word[$j] =~ /\bfor_/i && $word[$j+1] =~ /\bsure_/i)) { 
        	$word[$j] =~ s/_(\w+)/_$1 EMPH/;
    	}

    #---------------------------------------------------

    # Tags phrasal coordination with "and", "or" and "nor". 
    # ELF: Not currently in use due to relatively low precision and recall (see tagger performance evaluation).
    #if (($word[$j] =~ /\band_|\bor_|&_|\bnor_/i) &&
     # (($word[$j-1] =~ /_RB/ && $word[$j+1] =~ /_RB/) ||
      #($word[$j-1] =~ /_J/ && $word[$j+1] =~ /_J/) ||
      #($word[$j-1] =~ /_V/ && $word[$j+1] =~ /_V/) ||
      #($word[$j-1] =~ /_CD/ && $word[$j+1] =~ /_CD/) ||
      #($word[$j-1] =~ /_NN/ && $word[$j+1] =~ /_NN|whatever_|_DT/))) {
       #   $word[$j] =~ s/_\w+/_PHC/;
    #}
    
    #---------------------------------------------------
    
        # Tags auxiliary DO ELF: I added this variable and removed Nini's old pro-verb DO variable. Later on, all DO verbs not tagged as DOAUX here are tagged as ACT.
    if ($word[$j] =~ /\bdo_V|\bdoes_V|\bdid_V/i && $word[$j-1] !~ /to_TO/) { # This excludes DO + VB\b which have already been tagged as emphatics (DO_EMPH) and "to do" constructions
      if (($word[$j+2] =~ /_VB\b/) || # did you hurt yourself? Didn't look? 
        ($word[$j+3] =~ /_VB\b/) || # didn't it hurt?
        ($word[$j+1] =~ /_\W/) || # You did?
        ($word[$j+1] =~ /\bI_|\byou_|\bhe_|\bshe_|\bit_|\bwe_|\bthey_|_XX0/i && $word[$j+2] =~ /_\.|_VB\b/) || # ELF: Added to include question tags such as: "do you?"" or "He didn't!""
        ($word[$j+1] =~ /_XX0/ && $word[$j+2] =~ /\bI_|\byou_|\bhe_|\bshe_|\bit_|\bwe_|\bthey_|_VB\b/i) || # Allows for question tags such as: didn't you? as well as negated forms such as: did not like
        ($word[$j+1] =~ /\bI_|\byou_|\bhe_|\bshe_|\bit_|\bwe_|\bthey_/i && $word[$j+3] =~ /\?_\./) || # ELF: Added to include question tags such as: did you not? did you really?
        ($word[$j-1] =~ /(\b($wp))|(\b$who)|(\b$whw)/i)) {
          $word[$j] =~ s/_(\w+)/_$1 DOAUX/;
      }
    }
    
    #---------------------------------------------------    

    # Tags WH questions
    # ELF: rewrote this new operationalisation because Biber/Nini's code relied on a full stop appearing before the question word. 
    # This new operationalisation requires a question word (from a much shorter list taken from the COBUILD that Nini's/Biber's list) that is not followed by another question word and then a question mark within 15 words. 
    if (($word[$j] =~ /\b$whw/i && $word[$j+1] =~ /\?_\./)  ||
    	($word[$j] =~ /\b$whw/i && $word[$j+1] !~ /\b$whw/i && $word[$j+2] =~ /\?_\./) ||
    	($word[$j] =~ /\b$whw/i && $word[$j+1] !~ /\b$whw/i && $word[$j+3] =~ /\?_\./) ||
    	($word[$j] =~ /\b$whw/i && $word[$j+1] !~ /\b$whw/i && $word[$j+4] =~ /\?_\./) ||
    	($word[$j] =~ /\b$whw/i && $word[$j+1] !~ /\b$whw/i && $word[$j+5] =~ /\?_\./) ||
    	($word[$j] =~ /\b$whw/i && $word[$j+1] !~ /\b$whw/i && $word[$j+6] =~ /\?_\./) ||
    	($word[$j] =~ /\b$whw/i && $word[$j+1] !~ /\b$whw/i && $word[$j+7] =~ /\?_\./) ||
    	($word[$j] =~ /\b$whw/i && $word[$j+1] !~ /\b$whw/i && $word[$j+8] =~ /\?_\./) ||
    	($word[$j] =~ /\b$whw/i && $word[$j+1] !~ /\b$whw/i && $word[$j+9] =~ /\?_\./) ||
    	($word[$j] =~ /\b$whw/i && $word[$j+1] !~ /\b$whw/i && $word[$j+10] =~ /\?_\./) ||
    	($word[$j] =~ /\b$whw/i && $word[$j+1] !~ /\b$whw/i && $word[$j+11] =~ /\?_\./) ||
    	($word[$j] =~ /\b$whw/i && $word[$j+1] !~ /\b$whw/i && $word[$j+12] =~ /\?_\./) ||
    	($word[$j] =~ /\b$whw/i && $word[$j+1] !~ /\b$whw/i && $word[$j+13] =~ /\?_\./) ||
    	($word[$j] =~ /\b$whw/i && $word[$j+1] !~ /\b$whw/i && $word[$j+14] =~ /\?_\./) ||
    	($word[$j] =~ /\b$whw/i && $word[$j+1] !~ /\b$whw/i && $word[$j+15] =~ /\?_\./) ||
    	($word[$j] =~ /\b$whw/i && $word[$j+1] !~ /\b$whw/i && $word[$j+16] =~ /\?_\./)) {
          $word[$j] =~ s/(\w+)_(\w+)/$1_WHQU/;
    }
    
    #---------------------------------------------------    
  	# Tags yes/no inverted questions (YNQU)
  	# ELF: New variable
  	# Note that, at this stage in the script, DT still includes demonstrative pronouns which is good. Also _P, at this stage, only includes PRP, and PPS (i.e., not yet any of the new verb variables which should not be captured here)
  	
  	if (($word[$j-2] !~ /_WHQU|YNQU/ && $word[$j-1] !~ /_WHQU|YNQU/ && $word[$j] =~ /\b($be)|\b($have)|\b($do)|_MD/i && $word[$j+1] =~ /_P|_NN|_DT/ && $word[$j+3] =~ /\?_\./) ||  # Are they there? It is him?
  		($word[$j-2] !~ /_WHQU|YNQU/ && $word[$j-1] !~ /_WHQU|YNQU/ && $word[$j] =~ /\b($be)|\b($have)|\b($do)|_MD/i && $word[$j+1] =~ /_P|_NN|_DT|_XX0/ && $word[$j+4] =~ /\?_\./) || # Can you tell him?
  		($word[$j-2] !~ /_WHQU|YNQU/ && $word[$j-1] !~ /_WHQU|YNQU/ && $word[$j] =~ /\b($be)|\b($have)|\b($do)|_MD/i && $word[$j+1] =~ /_P|_NN|_DT|_XX0/ && $word[$j+5] =~ /\?_\./) || # Did her boss know that?
  		($word[$j-2] !~ /_WHQU|YNQU/ && $word[$j-1] !~ /_WHQU|YNQU/ && $word[$j] =~ /\b($be)|\b($have)|\b($do)|_MD/i && $word[$j+1] =~ /_P|_NN|_DT|_XX0/ && $word[$j+6] =~ /\?_\./) ||
  		($word[$j-2] !~ /_WHQU|YNQU/ && $word[$j-1] !~ /_WHQU|YNQU/ && $word[$j] =~ /\b($be)|\b($have)|\b($do)|_MD/i && $word[$j+1] =~ /_P|_NN|_DT|_XX0/ && $word[$j+7] =~ /\?_\./) ||
  		($word[$j-2] !~ /_WHQU|YNQU/ && $word[$j-1] !~ /_WHQU|YNQU/ && $word[$j] =~ /\b($be)|\b($have)|\b($do)|_MD/i && $word[$j+1] =~ /_P|_NN|_DT|_XX0/ && $word[$j+8] =~ /\?_\./) ||
  		($word[$j-2] !~ /_WHQU|YNQU/ && $word[$j-1] !~ /_WHQU|YNQU/ && $word[$j] =~ /\b($be)|\b($have)|\b($do)|_MD/i && $word[$j+1] =~ /_P|_NN|_DT|_XX0/ && $word[$j+9] =~ /\?_\./) ||
  		($word[$j-2] !~ /_WHQU|YNQU/ && $word[$j-1] !~ /_WHQU|YNQU/ && $word[$j] =~ /\b($be)|\b($have)|\b($do)|_MD/i && $word[$j+1] =~ /_P|_NN|_DT|_XX0/ && $word[$j+10] =~ /\?_\./) ||
  		($word[$j-2] !~ /_WHQU|YNQU/ && $word[$j-1] !~ /_WHQU|YNQU/ && $word[$j] =~ /\b($be)|\b($have)|\b($do)|_MD/i && $word[$j+1] =~ /_P|_NN|_DT|_XX0/ && $word[$j+11] =~ /\?_\./) ||
  		($word[$j-2] !~ /_WHQU|YNQU/ && $word[$j-1] !~ /_WHQU|YNQU/ && $word[$j] =~ /\b($be)|\b($have)|\b($do)|_MD/i && $word[$j+1] =~ /_P|_NN|_DT|_XX0/ && $word[$j+12] =~ /\?_\./) ||
  		($word[$j-2] !~ /_WHQU|YNQU/ && $word[$j-1] !~ /_WHQU|YNQU/ && $word[$j] =~ /\b($be)|\b($have)|\b($do)|_MD/i && $word[$j+1] =~ /_P|_NN|_DT|_XX0/ && $word[$j+13] =~ /\?_\./) ||
  		($word[$j-2] !~ /_WHQU|YNQU/ && $word[$j-1] !~ /_WHQU|YNQU/ && $word[$j] =~ /\b($be)|\b($have)|\b($do)|_MD/i && $word[$j+1] =~ /_P|_NN|_DT|_XX0/ && $word[$j+14] =~ /\?_\./) ||
  		($word[$j-2] !~ /_WHQU|YNQU/ && $word[$j-1] !~ /_WHQU|YNQU/ && $word[$j] =~ /\b($be)|\b($have)|\b($do)|_MD/i && $word[$j+1] =~ /_P|_NN|_DT|_XX0/ && $word[$j+15] =~ /\?_\./) ||
  		($word[$j-2] !~ /_WHQU|YNQU/ && $word[$j-1] !~ /_WHQU|YNQU/ && $word[$j] =~ /\b($be)|\b($have)|\b($do)|_MD/i && $word[$j+1] =~ /_P|_NN|_DT|_XX0/ && $word[$j+16] =~ /\?_\./)) {
      		$word[$j] =~ s/_(\w+)/_$1 YNQU/;
    }

    #---------------------------------------------------
    
    # Tags passives 
    # ELF: merged Biber's BYPA and PASS categories together into one and changed the original coding procedure on its head: this script now tags the past participles rather than the verb BE. It also allows for mistagging of -ed past participle forms as VBD by the Stanford Tagger.
    # ELF: I am including most "'s_VBZ" as a possible form of the verb BE here but later on overriding many instances as part of the PEAS variable.    
    
    if ($word[$j] =~ /_VBN|ed_VBD|en_VBD/) { # Also accounts for past participle forms ending in "ed" and "en" mistagged as past tense forms (VBD) by the Stanford Tagger
    
      if (($word[$j-1] =~ /\b($be)/i) || # is eaten 
      	#($word[$j-1] =~ /s_VBZ/i && $word[$j+1] =~ /\bby_/) || # This line enables the passive to be preferred over present perfect if immediately followed by a "by"
      	($word[$j-1] =~ /_RB|_XX0|_CC/ && $word[$j-2] =~ /\b($be)/i) || # isn't eaten 
        ($word[$j-1] =~ /_RB|_XX0|_CC/ && $word[$j-2] =~ /_RB|_XX0/ && $word[$j-3] =~ /\b($be)/i && $word[$j-3] !~ /\bs_VBZ/) || # isn't really eaten
        ($word[$j-1] =~ /_NN|_PRP|_CC/ && $word[$j-2] =~ /\b($be)/i)|| # is it eaten
        ($word[$j-1] =~ /_RB|_XX0|_CC/ && $word[$j-2] =~ /_NN|_PRP/ && $word[$j-3] =~ /\b($be)/i && $word[$j-3] !~ /\bs_VBZ/)) { # was she not failed?
            $word[$j] =~ s/_\w+/_PASS/;
      }
    }

	# ELF: Added a new variable for GET-passives
    if ($word[$j] =~ /_VBD|_VBN/) {
      if (($word[$j-1] =~ /\bget_V|\bgets_V|\bgot_V|\bgetting_V/i) ||
        ($word[$j-1] =~ /_NN|_PRP/ && $word[$j-2] =~ /\bget_V|\bgets_V|\bgot_V|\bgetting_V/i) || # She got it cleaned
        ($word[$j-1] =~ /_NN/ && $word[$j-2] =~ /_DT|_NN/ && $word[$j-3] =~ /\bget_V|\bgets_V|\bgot_V|\bgetting_V/i)) { # She got the car cleaned
    	$word[$j] =~ s/_\w+/_PGET/;
      }
    }
    

     #---------------------------------------------------
    
    # ELF: Added the new variable GOING TO, which allows for one intervening word between TO and the infinitive
    if (($word[$j] =~ /\bgoing_VBG/ && $word[$j+1] =~ /\bto_TO/ && $word[$j+2] =~ /\_VB/) ||
      ($word[$j] =~ /\bgoing_VBG/ && $word[$j+1] =~ /\bto_TO/ && $word[$j+3] =~ /\_VB/) ||
      ($word[$j] =~ /\bgon_VBG/ && $word[$j+1] =~ /\bna_TO/ && $word[$j+2] =~ /\_VB/) ||
      ($word[$j] =~ /\bgon_VBG/ && $word[$j+1] =~ /\bna_TO/ && $word[$j+3] =~ /\_VB/)) {
      $word[$j] =~ s/_\w+/_GTO/;
    }

    #---------------------------------------------------

    # Tags synthetic negation 
    # ELF: I'm merging this category with Biber's original analytic negation category (XX0) so I've had to move it further down in the script so it doesn't interfere with other complex tags
    if (($word[$j] =~ /\bno_/i && $word[$j+1] =~ /_J|_NN/) ||
      ($word[$j] =~ /\bneither_/i) ||
      ($word[$j] =~ /\bnor_/i)) {
        $word[$j] =~ s/_(\w+)/_XX0/;
    }
    # Added a loop to tag "no one" and "each other" as a QUPR
    if (($word[$j] =~ /\bno_/i && $word[$j+1] =~ /\bone_/) ||
    	($word[$j-1] =~ /\beach_/i && $word[$j] =~ /\bother_/)) {
    	$word[$j+1] =~ s/_(\w+)/_QUPR/;
    }

    #---------------------------------------------------

    # Tags split infinitives
    # ELF: merged this variable with split auxiliaries due to very low counts. Also removed "_AMPLIF|_DOWNTON" from these lists which Nini had but which made no sense because AMP and DWNT are a) tagged with shorter acronyms and b) this happens in future loops so RB does the job here. However, RB does not suffice for "n't" and not so I added _XX0 to the regex.
     
    if (($word[$j] =~ /\bto_/i && $word[$j+1] =~ /_RB|\bjust_|\breally_|\bmost_|\bmore_|_XX0/i && $word[$j+2] =~ /_V/) ||
      ($word[$j] =~ /\bto_/i && $word[$j+1] =~ /_RB|\bjust_|\breally_|\bmost_|\bmore_|_XX0/i && $word[$j+2] =~ /_RB|_XX0/ && $word[$j+3] =~ /_V/) ||

    # Tags split auxiliaries - ELF: merged this variable with split infinitives due to very low counts. ELF: changed all forms of DO to auxiliary DOs only 
      ($word[$j] =~ /_MD|DOAUX|(\b($have))|(\b($be))/i && $word[$j+1] =~ /_RB|\bjust_|\breally_|\bmost_|\bmore_/i && $word[$j+2] =~ /_V/) ||
      ($word[$j] =~ /_MD|DOAUX|(\b($have))|(\b($be))/i && $word[$j+1] =~ /_RB|\bjust_|\breally_|\bmost_|\bmore_|_XX0/i && $word[$j+2] =~ /_RB|_XX0/ && $word[$j+3] =~ /_V/)){
        $word[$j] =~ s/_(\w+)/_$1 SPLIT/;
    }


    #---------------------------------------------------

    # ELF: Attempted to add an alternative stranded "prepositions/particles" - This is currently not in use because it's too inaccurate.
    #if ($word[$j] =~ /\b($particles)_IN|\b($particles)_RP|\b($particles)_RB|to_TO/i && $word[$j+1] =~ /_\W/){
     # $word[$j] =~ s/_(\w+)/_$1 [STPR]/;
    #}

    # Tags stranded prepositions
    # ELF: changed completely since Nini's regex relied on PIN which is no longer a variable in use in the MFTE. 
    if ($word[$j] =~ /\b($preposition)|\bto_TO/i && $word[$j] !~ /_R/ && $word[$j+1] =~ /_\./){
      $word[$j] =~ s/_(\w+)/_$1 STPR/;
    }

    #---------------------------------------------------
    
    # Tags imperatives (in a rather crude way). 
    # ELF: This is a new variable.
    if (($word[$j-1] =~ /_\W|_EMO|_FW|_SYM/ && $word[$j-1] !~ /_:|_'|-RRB-/ && $word[$j] =~ /_VB\b/ && $word[$j] !~ /\bplease_|\bthank_| DOAUX|\b($be)/i && $word[$j+1] !~ /\bI_|\byou_|\bwe_|\bthey_|_NNP/i) || # E.g., "This is a task. Do it." # Added _SYM and _FW because imperatives often start with bullet points which are not always recognised as such. Also added _EMO for texts that use emoji/emoticons instead of punctuation.
     #($word[$j-2] =~ /_\W|_EMO|_FW|_SYM/  && $word[$j-2] !~ /_,/ && $word[$j-1] !~ /_MD/ && $word[$j] =~ /_VB\b/ && $word[$j] !~ /\bplease_|\bthank_| DOAUX|\b($be)/i && $word[$j+1] !~ /\bI_|\byou_|\bwe_|\bthey_|\b_NNP/i) || # Allows for one intervening token between end of previous sentence and imperative verb, e.g., "Just do it!". This line is not recommended for the Spoken BNC2014 and any texts with not particularly good punctuation.
      ($word[$j-2] =~ /_\W|_EMO|_FW|_SYM|_HST/ && $word[$j-2] !~ /_:|_,|_'|-RRB-/ && $word[$j-1] =~ /_RB|_CC|_DMA/ && $word[$j] =~ /_VB\b/ && $word[$j] !~ /\bplease_|\bthank_| DOAUX|\b($be)/i && $word[$j+1] !~ /\bI_|\byou_|\bwe_|\bthey_|_NNP/) || # "Listen carefully. Then fill the gaps."
      ($word[$j-1] =~ /_\W|_EMO|_FW|_SYM|_HST/ && $word[$j-1] !~ /_:|_,|_''|-RRB-/ && $word[$j] =~ /\bpractise_|\bmake_|\bcomplete/i) ||
      ($word[$j] =~ /\bPractise_|\bMake_|\bComplete_|\bMatch_|\bRead_|\bChoose_|\bWrite_|\bListen_|\bDraw_|\bExplain_|\bThink_|\bCheck_|\bDiscuss_/) || # Most frequent imperatives that start sentences in the Textbook English Corpus (TEC) (except "Answer" since it is genuinely also frequently used as a noun)
      ($word[$j-1] =~ /_\W|_EMO|_FW|_SYM|_HST/ && $word[$j-1] !~ /_:|_,|_'/ && $word[$j] =~ /\bdo_/i && $word[$j+1] =~ /_XX0/ && $word[$j+2] =~ /_VB\b/i) || # Do not write. Don't listen.      
      ($word[$j] =~ /\bwork_/i && $word[$j+1] =~ /\bin_/i && $word[$j+2] =~ /\bpairs_/i)) { # Work in pairs because it occurs 700+ times in the Textbook English Corpus (TEC) and "work" is always incorrectly tagged as a noun there.
      $word[$j] =~ s/_\w+/_VIMP/; 
    }

    if (($word[$j-2] =~ /_VIMP/ && $word[$j-1] =~ /\band_|\bor_|,_|&_/i && $word[$j] =~ /_VB\b/ && $word[$j] !~ /\bplease_|\bthank_| DOAUX/i) ||
    	($word[$j-3] =~ /_VIMP/ && $word[$j-1] =~ /\band_|\bor_|,_|&_/i && $word[$j] =~ /_VB\b/ && $word[$j] !~ /\bplease_|\bthank_| DOAUX/i) ||
    	($word[$j-4] =~ /_VIMP/ && $word[$j-1] =~ /\band_|\bor_|,_|&_/i && $word[$j] =~ /_VB\b/ && $word[$j] !~ /\bplease_|\bthank_| DOAUX/i)) {
      $word[$j] =~ s/_\w+/_VIMP/; # This accounts for, e.g., "read (carefully/the text) and listen"
    }
    
    #---------------------------------------------------

    # Tags 'that' adjective complements. 
    # ELF: added the _IN tag onto the "that" to improve accuracy but currently not in use because it still proves to0 errorprone.
    #if ($word[$j-1] =~ /_J/ && $word[$j] =~ /\bthat_IN/i) {
     # $word[$j] =~ s/_\w+/_THAC/;
    #}
    
    # ELF: tags other adjective complements. It's important that WHQU comes afterwards.
    # ELF: also currently not in use because of the high percentage of taggin errors.
    #if ($word[$j-1] =~ /_J/ && $word[$j] =~ /\bwho_|\bwhat_WP|\bwhere_|\bwhy_|\bhow_|\bwhich_/i) {
     # $word[$j] =~ s/_\w+/_WHAC/;
    #}
    
    #---------------------------------------------------

	# ELF: Removed Biber's complex and, without manual adjustments, highly unreliable variables WHSUB, WHOBJ, THSUB, THVC, and TOBJ and replaced them with much simpler variables. It should be noted, however, that these variables rely much more on the Stanford Tagger which is far from perfect depending on the type of texts to be tagged. Thorough manual checks are highly recommended before using the counts of these variables!
      
	# That-subordinate clauses other than relatives according to the Stanford Tagger  
    if ($word[$j] =~ /\bthat_IN/i && $word[$j+1] !~ /_\W/) {
      $word[$j] =~ s/_\w+/_THSC/;
      }
    
    # That-relative clauses according to the Stanford Tagger  
    if ($word[$j] =~ /\bthat_WDT/i && $word[$j+1] !~ /_\W/) {
      $word[$j] =~ s/_\w+/_THRC/;
      }      
      
	# Subordinate clauses with WH-words. 
	# ELF: New variable.
    if ($word[$j] =~ /\b($wp)|\b($who)/i && $word[$j] !~ /_WHQU/) {
      $word[$j] =~ s/_\w+/_WHSC/;
      }
      
    #---------------------------------------------------

    # Tags hedges 
    # ELF: added "kinda" and "sorta" and corrected the "sort of" and "kind of" lines in Nini's original script which had the word-2 part negated.
    # Also added apparently, conceivably, perhaps, possibly, presumably, probably, roughly and somewhat.
    if (($word[$j] =~ /\bmaybe_|apparently_|conceivably_|perhaps_|\bpossibly_|presumably_|\bprobably_|\broughly_|somewhat_/i) ||
      ($word[$j] =~ /\baround_|\babout_/i && $word[$j+1] =~ /_CD|_QUAN/i)) {
          $word[$j] =~ s/_\w+/_HDG/;
          }
	
	if (($word[$j-1] =~ /\bat_/i && $word[$j] =~ /\babout_/i) ||
      ($word[$j-1] =~ /\bsomething_/i && $word[$j] =~ /\blike_/i) ||
      ($word[$j-2] !~ /_DT|_QUAN|_CD|_J|_PRP|(\b$who)/i && $word[$j-1] =~ /\bsort_/i && $word[$j] =~ /\bof_/i) ||
      ($word[$j-2] !~ /_DT|_QUAN|_CD|_J|_PRP|(\b$who)/i && $word[$j-1] =~ /\bkind_NN/i && $word[$j] =~ /\bof_/i) ||
      ($word[$j-1] !~ /_DT|_QUAN|_CD|_J|_PRP|(\b$who)/i && $word[$j] =~ /\bkinda_|\bsorta_/i)) {
      $word[$j] =~ s/_(\w+)/_$1 HDG/;
    }
    
     if ($word[$j-2] =~ /\bmore_/i && $word[$j-1] =~ /\bor_/i && $word[$j] =~ /\bless_/i) {
      $word[$j] =~ s/_\w+/_QUAN HDG/;
      $word[$j-2] =~ s/\w+/_QUAN/;
     }

    
    #---------------------------------------------------
   
    # Tags politeness markers
    # ELF new variables for: thanks, thank you, ta, please, mind_VB, excuse_V, sorry, apology and apologies.
    if (($word[$j] =~ /\bthank_/i && $word[$j+1] =~ /\byou/i) ||
      ($word[$j] =~ /\bsorry_|\bexcuse_V|\bapology_|\bapologies_|\bplease_|\bcheers_/i) ||
      ($word[$j] =~ /\bthanks_/i && $word[$j+1] !~ /\bto_/i) || # Avoids the confusion with the conjunction "thanks to"
      ($word[$j-1] !~ /\bgot_/i && $word[$j] =~ /\bta_/i) || # Avoids confusion with gotta
      ($word[$j-2] =~ /\bI_|\bwe_/i && $word[$j-1] =~ /\b($be)/i && $word[$j] =~ /\bwonder_V|\bwondering_/i) ||
      ($word[$j-1] =~ /\byou_|_XX0/i && $word[$j] =~ /\bmind_V/i)) {
      $word[$j] =~ s/_(\w+)/_$1 POLITE/;
    }
    
    # Tags HAVE GOT constructions
    # ELF: New variable.
    if ($word[$j] =~ /\bgot/i) {
      if (($word[$j-1] =~ /\b($have)/i) || # have got
        ($word[$j-1] =~ /_RB|_XX0|_EMPH|_DMA/ && $word[$j-2] =~ /\b($have)/i) || # have not got
        ($word[$j-1] =~ /_RB|_XX0|_EMPH|_DMA/ && $word[$j-2] =~ /_RB|_XX0|_EMPH|_DMA/ && $word[$j-3] =~ /\b($have)/i) || # haven't they got
        ($word[$j-1] =~ /_NN|\bi_|\bwe_|\bhe_|\bshe_|\bit_P|\bthey_/ && $word[$j-2] =~ /\b($have)/i) || # has he got?
        ($word[$j-1] =~ /_XX0|_RB|_EMPH|_DMA/ && $word[$j-2] =~ /_NN|\bi_|\bwe_|\bhe_|\bshe_|\bit_P|\bthey_/ && $word[$j-3] =~ /\b($have)/i)) { # hasn't he got?
            $word[$j] =~ s/_\w+/_HGOT/;
      }
      if ($word[$j-1] =~ /\b($have)/i && $word[$j+1] =~ /_VBD|_VBN/) {
      		$word[$j] =~ s/_(\w+)/_PEAS/;
      		$word[$j+1] =~ s/_(\w+)/_PGET/;
      } # Correction for: she has got arrested
      
      if ($word[$j-2] =~ /\b($have)/i && $word[$j-1] =~ /_RB|_XX0|_EMPH|_DMA/i && $word[$j+1] =~ /_VBD|_VBN/) {
            $word[$j] =~ s/_(\w+)/_PEAS/;
      		$word[$j+1] =~ s/_(\w+)/_PGET/;
      } # Correction for: she hasn't got arrested
    }

  }

      #---------------------------------------------------

  
# EVEN MORE COMPLEX TAGS
  
      for ($j=0; $j<@word; $j++) {  

      #---------------------------------------------------
           
    # Tags remaining attribute adjectives (JJAT)

    if (($word[$j-2] =~ /_JJAT/ && $word[$j-1] =~ /\band_/i && $word[$j] =~ /_JJ/) ||
    	($word[$j] =~ /_JJ/ && $word[$j+1] =~ /\band_/i && $word[$j+2] =~ /_JJAT/) ||
    	($word[$j-2] =~ /_JJAT/ && $word[$j-1] =~ /,_,/ && $word[$j] =~ /_JJ/) ||
    	($word[$j] =~ /_JJ/ && $word[$j+1] =~ /,_,/ && $word[$j+2] =~ /_JJAT/) ||
    	($word[$j] =~ /_JJ/ && $word[$j+1] =~ /,_,/ && $word[$j+2] =~ /\band_/ && $word[$j+3] =~ /_JJAT/) ||
    	($word[$j-3] =~ /_JJAT/ && $word[$j-2] =~ /,_,/ && $word[$j-1] =~ /\band_/ && $word[$j] =~ /_JJ/)) {
        $word[$j] =~ s/_\w+/_JJAT/;
    }
    
      #---------------------------------------------------
    
      # Tags perfect aspects # ELF: Changed things around to tag PEAS onto the past participle (and thus replace the VBD/VBN tags) rather than as an add-on to the verb have, as Biber/Nini did. 
      # I tried to avoid as many errors as possible with 's being either BE (= passive) or HAS (= perfect aspect) but this is not perfect. Note that "'s got" and "'s used to" are already tagged separately. 
      # Also note that lemmatisation would not have helped much here because spot checks with Sketch Engine's lemmatiser show that lemmatisers do a terrible job at this, too!
      
    if (($word[$j] =~ /ed_VBD|_VBN/ && $word[$j-1] =~ /\b($have)/i) || # have eaten
        ($word[$j] =~ /ed_VBD|_VBN/ && $word[$j-1] =~ /_RB|_XX0|_EMPH|_PRP|_DMA|_CC/ && $word[$j-2] =~ /\b($have)/i) || # have not eaten
        ($word[$j] =~ /\bbeen_PASS|\bhad_PASS|\bdone_PASS|\b($v_stative)_PASS/i && $word[$j-1] =~ /\bs_VBZ/i) || # This ensures that 's + past participle combinations which are unlikely to be passives are overwritten here as PEAS
        ($word[$j] =~ /\bbeen_PASS|\bhad_PASS|\bdone_PASS|\b($v_stative)_PASS/i && $word[$j-1] =~ /_RB|_XX0|_EMPH|_DMA/ && $word[$j-2] =~ /\bs_VBZ/i) || # This ensures that 's + not/ADV + past participle combinations which are unlikely to be passives are overwritten here as PEAS
        ($word[$j] =~ /ed_VBD|_VBN/ && $word[$j-2] =~ /_RB|_XX0|_EMPH|_CC/ && $word[$j-3] =~ /\b($have)/i) || # haven't really eaten, haven't you noticed?
        ($word[$j] =~ /ed_VBD|_VBN/ && $word[$j-1] =~ /_NN|\bi_|\bwe_|\bhe_|\bshe_|\bit_P|\bthey_/ && $word[$j-2] =~ /\b($have)/i) || # has he eaten?
        ($word[$j-1] =~ /\b($have)/i && $word[$j] =~ /ed_VBD|_VBN/ && $word[$j+1] =~ /_P/) || # has been told or has got arrested
        ($word[$j] =~ /ed_VBD|_VBN/ && $word[$j+1] =~ /_P/ && $word[$j-1] =~ /_XX0|_RB|_EMPH|_DMA|_CC/ && $word[$j-2] =~ /_XX0|_RB|_EMPH/ && $word[$j-3] =~ /\b($have)/i) || #hasn't really been told
        ($word[$j] =~ /ed_VBD|_VBN/ && $word[$j+1] =~ /_PASS/ && $word[$j-1] =~ /_XX0|_RB|_EMPH|_DMA|_CC/ && $word[$j-2] =~ /\b($have)/i) || # hasn't been told
        ($word[$j] =~ /ed_VBD|_VBN/ && $word[$j+1] =~ /_XX0|_EMPH|_DMA|_CC/ && $word[$j-1] =~ /_NN|\bi_|\bwe_|\bhe_|\bshe_|\bit_P|\bthey_/ && $word[$j-2] =~ /\b($have)/i)) { # hasn't he eaten?
     $word[$j] =~ s/_\w+/_PEAS/;
    }
 
 # This corrects some of the 'd wrongly identified as a modal "would" by the Stanford Tagger 
     if ($word[$j-1] =~ /'d_MD/i && $word[$j] =~ /_VBN/) { # He'd eaten
    	$word[$j-1] =~ s/_\w+/_VBD/;
    	$word[$j] =~ s/_\w+/_PEAS/;
    }   
    if ($word[$j-1] =~ /'d_MD/i && $word[$j] =~ /_RB|_EMPH/ && $word[$j+1] =~ /_VBN/) { # She'd never been
    	$word[$j-1] =~ s/_\w+/_VBD/;
    	$word[$j+1] =~ s/_\w+/_PEAS/;
    }

    
 # This corrects some of the 'd wrongly identified as a modal "would" by the Stanford Tagger 
     if ($word[$j] =~ /\bbetter_/ && $word[$j-1] =~ /'d_MD/i) {
    	$word[$j-1] =~ s/_\w+/_VBD/;
    }
    
    if ($word[$j] =~ /_VBN|ed_VBD|en_VBD/ && $word[$j-1] =~ /\band_|\bor_/i && $word[$j-2] =~ /_PASS/)  { # This accounts for the second passive form in phrases such as "they were selected and extracted"
            $word[$j-1] =~ s/_\w+/_CC/; # OR _PHC if this variable is used! (see problems described in tagger performance evaluation)
            $word[$j] =~ s/_\w+/_PASS/;
    }
            
    # ELF: Added a "used to" variable, overriding the PEAS and PASS constructions. Not currently in use due to very low precision (see tagger performance evaluation).
    #if ($word[$j] =~ /\bused_/i && $word[$j+1] =~ /\bto_/) {
     # $word[$j] =~ s/_\w+/_USEDTO/;
    #}
    
    # ELF: tags "able to" constructions. New variable
    if (($word[$j-1] =~ /\b($be)/ && $word[$j] =~ /\bable_JJ|\bunable_JJ/i && $word[$j+1] =~ /\bto_/) ||
     	($word[$j-2] =~ /\b($be)/ && $word[$j] =~ /\bable_JJ|\bunable_JJ/i && $word[$j+1] =~ /\bto_/)) {
      $word[$j] =~ s/_\w+/_ABLE/;
    }
    

  }
      

  #---------------------------------------------------
    
    # ELF: Added a tag for "have got" constructions, overriding the PEAS and PASS constructions.
    
    for ($j=0; $j<@word; $j++) {  
    

  # ELF: tags question tags. New variable
  
  
    if (($word[$j-6] !~ /_WHQU/ && $word[$j-5] !~ /_WHQU/ && $word[$j-4] !~ /_WHQU/ && $word[$j-3] =~ /_MD|\bdid_|\bhad_/i && $word[$j-2] =~ /_XX0/ && $word[$j-1] =~ /_PRP|\bi_|\bwe_|\bhe_|\bshe_|\bit_P|\bthey_/ && $word[$j] =~ /\?_\./) || # couldn't he?
    
    	($word[$j-6] !~ /_WHQU/ && $word[$j-5] !~ /_WHQU/ && $word[$j-4] !~ /_WHQU/ && $word[$j-3] !~ /_WHQU/ && $word[$j-2] =~ /_MD|\bdid_|\bhad_/i && $word[$j-1] =~ /_PRP|\bi_|\bwe_|\bhe_|\bshe_|\bit_P|\bthey_/ && $word[$j] =~ /\?_\./) || # did they?
    	
    	($word[$j-6] !~ /_WHQU/ && $word[$j-5] !~ /_WHQU/ && $word[$j-4] !~ /_WHQU/ && $word[$j-3] =~ /\bis_|\bdoes_|\bwas|\bhas/i && $word[$j-2] =~ /_XX0/ && $word[$j-1] =~ /\bit_|\bshe_|\bhe_/i && $word[$j] =~ /\?_\./)  || # isn't it?
    	
    	($word[$j-6] !~ /_WHQU/ && $word[$j-5] !~ /_WHQU/ && $word[$j-4] !~ /_WHQU/ && $word[$j-3] !~ /_WHQU/ && $word[$j-2] =~ /\bis_|\bdoes_|\bwas|\bhas_/i && $word[$j-1] =~ /\bit_|\bshe_|\bhe_/i && $word[$j] =~ /\?_\./)  || # has she?
    	
    	($word[$j-6] !~ /_WHQU/ && $word[$j-5] !~ /_WHQU/ && $word[$j-4] !~ /_WHQU/ && $word[$j-3] =~ /\bdo|\bwere|\bare|\bhave/i && $word[$j-2] =~ /_XX0/ && $word[$j-1] =~ /\byou_|\bwe_|\bthey_/i && $word[$j] =~ /\?_\./)  || # haven't you?
    	
    	($word[$j-6] !~ /_WHQU/ && $word[$j-5] !~ /_WHQU/ && $word[$j-4] !~ /_WHQU/ && $word[$j-3] !~ /_WHQU/ && $word[$j-2] =~ /\bdo|\bwere|\bare|\bhave/i && $word[$j-1] =~ /\byou_|\bwe_|\bthey_/i && $word[$j] =~ /\?_\./) || # were you?
    	
    	($word[$j-1] =~ /\binnit_|\binit_/ && $word[$j] =~ /\?_\./)) { # innit? init?
    	
         	$word[$j] =~ s/_(\W+)/_$1 QUTAG/;
    }
  }
  
        #---------------------------------------------------
    

    # ELF: added tag for progressive aspects (initially modelled on Nini's algorithm for the perfect aspect). 
    # Note that it's important that this tag has its own loop because it relies on GTO (going to + inf. constructions) having previously been tagged. 
    # Note that this script overrides the _VBG Stanford tagger tag so that the VBG count are now all -ing constructions *except* progressives and GOING-to constructions.
  
    for ($j=0; $j<@word; $j++) {
  
    if ($word[$j] =~ /_VBG/) {
      if (($word[$j-1] =~ /\b($be)/i) || # am eating
        ($word[$j-1] =~ /_RB|_XX0|_EMPH|_CC/ && $word[$j-2] =~ /\b($be)|'m_V/i) || # am not eating
        ($word[$j-1] =~ /_RB|_XX0|_EMPH|_CC/ && $word[$j-2] =~ /_RB|_XX0|_EMPH|_CC/ && $word[$j-3] =~ /\b($be)/i) || # am not really eating
        ($word[$j-1] =~ /_NN|_PRP|\bi_|\bwe_|\bhe_|\bshe_|\bit_P|\bthey_/ && $word[$j-2] =~ /\b($be)/i) || # am I eating
        ($word[$j-1] =~ /_NN|_PRP|\bi_|\bwe_|\bhe_|\bshe_|\bit_P|\bthey_/ && $word[$j-2] =~ /_XX0|_EMPH/ && $word[$j-3] =~ /\b($be)/i) || # aren't I eating?
        ($word[$j-1] =~ /_XX0|_EMPH/ && $word[$j-2] =~ /_NN|_PRP|\bi_|\bwe_|\bhe_|\bshe_|\bit_P|\bthey_/ && $word[$j-3] =~ /\b($be)/i)) { # am I not eating
            $word[$j] =~ s/_\w+/_PROG/;
      }
    }
    
        #---------------------------------------------------
    
    # ELF: Added two new variables for "like" as a preposition (IN) and adjective (JJ) because it most often does not seem to be a preposition (but rather a filler, part of the quotative phrase BE+like, etc.) and should therefore not be added to the preposition count unless it is followed by a noun or adjective.
    # ELF: QLIKE is currently in use due to relatively low precision and recall (see tagger performance evaluation).
      
     #if ($word[$j-1] =~ /\b($be)/ && $word[$j] =~ /\blike_IN|\blike_JJ/i && $word[$j+1] !~ /_NN|_J|_DT|_\.|_,|_IN/) {

      #$word[$j] =~ s/_\w+/_QLIKE/;
    #}
  
     if ($word[$j] =~ /\blike_IN|\blike_JJ|\blike_JJ/i) {

     $word[$j] =~ s/_\w+/_LIKE/;
    }
    
  }
    
    #---------------------------------------------------

    # Tags be as main verb ELF: Ensured that question tags are not being assigned this tag by adding the exceptions of QUTAG occurrences.
    
    for ($j=0; $j<@word; $j++) {  

    if (($word[$j-2] !~ /_EX/ && $word[$j-1] !~ /_EX/ && $word[$j] =~ /\b($be)|\bbeen_/i && $word[$j+1] =~ /_CD|_DT|_PRP|_J|_IN|_QUAN|_EMPH|_CUZ/ && $word[$j+2] !~ /QUTAG|_PROG/ && $word[$j+3] !~ /QUTAG|_PROG/) ||
    
    ($word[$j-2] !~ /_EX/ && $word[$j-1] !~ /_EX/ && $word[$j] =~ /\b($be)|\bbeen_/i && $word[$j+1] =~ /_NN/ && $word[$j+2] =~ /\W+_/ && $word[$j+2] !~ / QUTAG|_PROG/) || # Who is Dinah? Ferrets are ferrets!

    ($word[$j-2] !~ /_EX/ && $word[$j-1] !~ /_EX/ && $word[$j] =~ /\b($be)|\bbeen_/i && $word[$j+1] =~ /_CD|_DT|_PRP|_J|_IN|_QUAN|_RB|_EMPH|_NN/ && $word[$j+2] =~ /_CD|_DT|_PRP|_J|_IN|_QUAN|to_TO|_EMPH/ && $word[$j+2] !~ /QUTAG|_PROG|_PASS/ && $word[$j+3] !~ /QUTAG|_PROG|_PASS/ && $word[$j+4] !~ / QUTAG|_PROG|_PASS/) || # She was so much frightened
    
    ($word[$j-2] !~ /_EX/ && $word[$j-1] !~ /_EX/ && $word[$j] =~ /\b($be)|\bbeen_/i && $word[$j+1] =~ /_RB|_XX0/ && $word[$j+2] =~ /_CD|_DT|_PRP|_J|_IN|_QUAN|_EMPH/ && $word[$j+2] !~ / QUTAG|_PROG|_PASS/ && $word[$j+3] !~ / QUTAG|_PROG|_PASS/)) {
        
        $word[$j] =~ s/_(\w+)/_$1 BEMA/;  
    }
  }
  
  #---------------------------------------------------
  # Tags demonstratives 
  # ELF: New, much simpler variable. Also corrects any leftover "that_IN" and "that_WDT" to DEMO. 
  # These have usually been falsely tagged by the Stanford Tagger, especially they end sentences, e.g.: Who did that?

  for ($j=0; $j<@word; $j++) {

    if ($word[$j] =~ /\bthat_DT|\bthis_DT|\bthese_DT|\bthose_DT|\bthat_IN|\bthat_WDT/i) {
      $word[$j] =~ s/_\w+/_DEMO/;
    }  
  }
  
  
  #---------------------------------------------------
  # Tags subordinator-that deletion 
  # ELF: Added $word+2 in the first pattern to remove "Why would I know that?", 
  # replaced the long MD/do/have/be/V regex that had a lot of redundancies by just MD/V. 
  # In the second pattern, replaced all PRPS by just subject position ones to remove phrases like "He didn't hear me thank God". 
  # Originally also added the pronoun "it" which Nini had presumably forgotten. Then simply used the PRP tag for all personal pronouns.

  for ($j=0; $j<@word; $j++) {

    if (($word[$j] =~ /\b($public|$private|$suasive)/i && $word[$j+1] =~ /_DEMO|_PRP|_N/ && $word[$j+2]=~ /_MD|_V/) ||
    
      ($word[$j] =~ /\b($public|$private|$suasive)/i && $word[$j+1] =~ /_PRP|_N/ && $word[$j+2] =~ /_MD|_V/) ||
      
      ($word[$j] =~ /\b($public|$private|$suasive)/i && $word[$j+1] =~ /_J|_RB|_DT|_QUAN|_CD|_PRP/ && $word[$j+2] =~ /_N/ && $word[$j+3] =~ /_MD|_V/) ||
      
      ($word[$j] =~ /\b($public|$private|$suasive)/i && $word[$j+1] =~ /_J|_RB|_DT|_QUAN|_CD|_PRP/ && $word[$j+2] =~ /_J/ && $word[$j+3] =~ /_N/ && $word[$j+4] =~ /_MD|_V/)) {
      
      $word[$j] =~ s/_(\w+)/_$1 THATD/;
    }
  }

  
        #---------------------------------------------------
   
  
    # Tags pronoun it ELF: excluded IT (all caps) from the list since it usually refers to information technology

  
  for ($j=0; $j<@word; $j++) {  
  
    if (($word[$j] =~ /\bits_|\bitself_/i) ||
    	($word[$j] =~ /\bit_|\bIt_/)) {
      		$word[$j] =~ s/_\w+/_PIT/;
      }
    }
    
  #---------------------------------------------------
    
    # Tags first person pronouns ELF: Added exclusion of occurrences of US (all caps) which usually refer to the United States.
    # ELF: Added 's_PRP to account for abbreviated "us" in "let's" Also added: mine, ours.
    # ELF: Subdivided Biber's FPP1 into singular (interactant = speaker) and plural (interactant = speaker and others).
    
  for ($j=0; $j<@word; $j++) {  
    
    if ($word[$j] =~ /\bI_P|\bme_|\bmy_|\bmyself_|\bmine_|\bi_SYM|\bi_FW/i) {
      		$word[$j] =~ s/_\w+/_FPP1S/;
      }
      
    if (($word[$j] =~ /\bwe_|\bour_|\bourselves_|\bours_|'s_PRP/i) ||
     	($word[$j] =~ /\bus_P|\bUs_P/)) {
      		$word[$j] =~ s/_\w+/_FPP1P/;
      }
      
    if ($word[$j] =~ /\blet_/i && $word[$j+1] =~ /'s_|\bus_/i) {
    		$word[$j] =~ s/_\w+/_VIMP/;
    		$word[$j+1] =~ s/_\w+/_FPP1P/;
      }
    
    if ($word[$j] =~ /\blet_/i && $word[$j+1] =~ /\bme_/i) {
    		$word[$j] =~ s/_\w+/_VIMP/;
    		$word[$j+1] =~ s/_\w+/_FPP1S/;
      }
  
      
    }
    
  #---------------------------------------------------
    
  for ($j=0; $j<@word; $j++) {  
    
       # Tags concessive conjunctions 
       # Nini had already added "THO" to Biber's list.
       # ELF added: despite, albeit, yet, except that, in spite of, granted that, granted + punctuation, no matter + WH-words, regardless of + WH-word. 
       # Also added: nevertheless, nonetheless and notwithstanding and whereas, which Biber had as "other adverbial subordinators" (OSUB, a category ELF removed).
       
    if (($word[$j] =~ /\balthough_|\btho_|\bdespite|\balbeit_|nevertheless_|nonetheless_|notwithstanding_|\bwhereas_/i) ||
		($word[$j] =~ /\bexcept_/i && $word[$j+1] =~ /\bthat_/i) ||    	
		($word[$j] =~ /\bgranted_/i && $word[$j+1] =~ /\bthat_|_,/i) ||		
		($word[$j] =~ /\bregardless_|\birregardless_/i && $word[$j+1] =~ /\bof_/i) ||
    	($word[$j] =~ /\byet_|\bstill_/i && $word[$j+1] =~ /_,/i) ||
    	($word[$j-1] !~ /\bas_/i && $word[$j] =~ /\bthough_/i) ||
    	($word[$j] =~ /\byet_|\bgranted_|\bstill_/i && $word[$j-1] =~ /_\W/i)) {
     	 	$word[$j] =~ s/_\w+/_CONC/;
    	}

    if (($word[$j-1] =~ /\bno_/i && $word[$j] =~ /\bmatter_/i && $word[$j+1] =~ /\b$whw/i) ||
    	($word[$j-1] =~ /\bin_/i && $word[$j] =~ /\bspite_/ && $word[$j+1] =~ /\bof_/)) {
     	 	$word[$j] =~ s/_(\w+)/_$1 CONC/;
   	 	} 

    #---------------------------------------------------

    # Tags place adverbials 
    # ELF: added all the words from "downwind" onwards and excluded "there" tagged as an existential "there" as in "there are probably lots of bugs in this script". Also restricted above, around, away, behind, below, beside, inside and outside to adverb forms only.
    if ($word[$j] =~ /\baboard_|\babove_RB|\babroad_|\bacross_RB|\bahead_|\banywhere_|\balongside_|\baround_RB|\bashore_|\bastern_|\baway_RB|\bbackwards?|\bbehind_RB|\bbelow_RB|\bbeneath_|\bbeside_RB|\bdownhill_|\bdownstairs_|\bdownstream_|\bdownwards_|\beast_|\bhereabouts_|\bindoors_|\binland_|\binshore_|\binside_RB|\blocally_|\bnear_|\bnearby_|\bnorth_|\bnowhere_|\boutdoors_|\boutside_RB|\boverboard_|\boverland_|\boverseas_|\bsouth_|\bunderfoot_|\bunderground_|\bunderneath_|\buphill_|\bupstairs_|\bupstream_|\bupwards?|\bwest_|\bdownwind|\beastwards?|\bwestwards?|\bnorthwards?|\bsouthwards?|\belsewhere|\beverywhere|\bhere_|\boffshore|\bsomewhere|\bthereabouts?|\bfar_RB|\bthere_RB|\bonline_|\boffline_N/i 
    && $word[$j] !~ /_NNP/) {
        $word[$j] =~ s/_\w+/_PLACE/;
    }
    
    if ($word[$j] =~ /\bthere_P/i && $word[$j+1] =~ /_MD/) { # Correction of there + modals, e.g. there might be that option which are frequently not recognised as instances of there_EX by the Stanford Tagger
        $word[$j] =~ s/_\w+/_EX/;
    }

    #---------------------------------------------------

    # Tags time adverbials 
    # ELF: Added already, so far, thus far, yet (if not already tagged as CONC above) and ago. Restricted after and before to adverb forms only.
    if (($word[$j] =~ /\bago_|\bafter_RB|\bafterwards_|\bagain_|\balready_|\bbefore_RB|\bbeforehand_|\bbriefly_|\bcurrently_|\bearlier_|\bearly_RB|\beventually_|\bformerly_|\bimmediately_|\binitially_|\binstantly_|\bforeever_|\blate_RB|\blately_|\blater_|\bmomentarily_|\bnow_|\bnowadays_|\bonce_|\boriginally_|\bpresently_|\bpreviously_|\brecently_|\bshortly_|\bsimultaneously_|\bsooner_|\bsubsequently_|\bsuddenly|\btoday_|\bto-day_|\btomorrow_|\bto-morrow_|\btonight_|\bto-night_|\byesterday_|\byet_RB|\bam_RB|\bpm_RB/i) ||
    	($word[$j] =~ /\bsoon_/i && $word[$j+1] !~ /\bas_/i) ||
    	($word[$j] =~ /\bprior_/i && $word[$j+1] =~ /\bto_/i) ||
    	($word[$j-1] =~ /\bso_|\bthus_/i && $word[$j] =~ /\bfar_/i && $word[$j+1] !~ /_J|_RB/i)) {
      $word[$j] =~ s/_\w+/_TIME/;
    	}
    	
	}
   	 
    #---------------------------------------------------
    
    # Tags pro-verb do ELF: This is an entirely new way to operationalise the variable. Instead of identifying the pro-verb DO, I actually identify DO as an auxiliary early (DOAUX) and here I take other forms of DO as a verb as pro-verbs. This is much more reliable than Nini's method which, among other problems, tagged all question tags as the pro-verb DO. 
    # ELF: Following discussing with PU on the true definition of pro-verbs, removed this variable altogether and adding all non-auxiliary DOs to the activity verb list.
    
  for ($j=0; $j<@word; $j++) {  
    
    if ($word[$j] =~ /\b($do)/i && $word[$j] !~ / DOAUX/) {
      $word[$j] =~ s/_(\w+)/_$1 ACT/;
      }
      
    # Adds "NEED to" and "HAVE to" to the list of necessity (semi-)modals  
    if ($word[$j] =~ /\bneed_V|\bneeds_V|\bneeded_V|\bhave_V|\bhas_V|\bhad_V|\bhaving_V/i && $word[$j+1] =~ /\bto_TO/) {
      $word[$j] =~ s/_(\w+)/_MDNE/;
      }
      
    }
  
    
  #--------------------------------------------------- 
  
  # BASIC TAGS THAT HAVE TO BE TAGGED AT THE END TO AVOID CLASHES WITH MORE COMPLEX REGEX ABOVE
  foreach $x (@word) {

    # Tags amplifiers 
    # ELF: Added "more" as an adverb (note that "more" as an adjective is tagged as a quantifier further up)
    if ($x =~ /\babsolutely_|\baltogether_|\bcompletely_|\benormously_|\bentirely_|\bextremely_|\bfully_|\bgreatly_|\bhighly_|\bintensely_|\bmore_RB|\bperfectly_|\bstrongly_|\bthoroughly_|\btotally_|\butterly_|\bvery_/i) {
      $x =~ s/_\w+/_AMP/;
    }

    # Tags downtoners
    # ELF: Added "less" as an adverb (note that "less" as an adjective is tagged as a quantifier further up)
    # ELF: Removed "only" because it fulfils too many different functions.
    if ($x =~ /\balmost_|\bbarely_|\bhardly_|\bless_JJ|\bmerely_|\bmildly_|\bnearly_|\bpartially_|\bpartly_|\bpractically_|\bscarcely_|\bslightly_|\bsomewhat_/i) {
      $x =~ s/_\w+/_DWNT/;
    }
   
    # Corrects EMO tags
    # ELF: Correction of emoticon issues to do with the Stanford tags for brackets including hyphens
    if ($x =~ /_EMO(.)*-/i) {
      $x =~ s/_EMO(.)*-/_EMO/;
    }
    
    
    # Tags quantifier pronouns 
    # ELF: Added any, removed nowhere (which is now place). "no one" is also tagged for at an earlier stage to avoid collisions with the XX0 variable.
    if ($x =~ /\banybody_|\banyone_|\banything_|\beverybody_|\beveryone_|\beverything_|\bnobody_|\bnone_|\bnothing_|\bsomebody_|\bsomeone_|\bsomething_|\bsomewhere|\bnoone_|\bno-one_/i) {      
    $x =~ s/_\w+/_QUPR/;
    }

    # Tags nominalisations à la Biber (1988)
    # ELF: Not in use in this version of the MFTE due to frequent words skewing results, e.g.: activity, document, element...
    #if ($x =~ /tions?_NN|ments?_NN|ness_NN|nesses_NN|ity_NN|ities_NN/i) {
     # $x =~ s/_\w+/_NOMZ/;
    #}

    # Tags gerunds 
    # ELF: Not currently in use because of doubts about the usefulness of this category (cf. Herbst 2016 in Applied Construction Grammar) + high rate of false positives with Biber's/Nini's operationalisation of the variable.
    #if (($x =~ /ing_NN/i && $x =~ /\w{10,}/) ||
     # ($x =~ /ings_NN/i && $x =~ /\w{11,}/)) {
      #$x =~ s/_\w+/_GER/;
    #}
    
    # ELF added: pools together all proper nouns (singular and plural). Not currently in use since no distinction is made between common and proper nouns.
    #if ($x =~ /_NNPS/) {
     # $x =~ s/_\w+/_NNP/;
    #}
        
    # Tags predicative adjectives (JJPR) by joining all kinds of JJ (but not JJAT, see earlier loop)
    if ($x =~ /_JJS|_JJR|_JJ\b/) {
      $x =~ s/_\w+/_JJPR/;
    }

    # Tags total adverbs by joining all kinds of RB (but not those already tagged as HDG, FREQ, AMP, DWNTN, EMPH, ELAB, EXTD, TIME, PLACE...).
    if ($x =~ /_RBS|_RBR|_WRB/) {
      $x =~ s/_\w+/_RB/;
    }

    # Tags present tenses
    if ($x =~ /_VBP|_VBZ/) {
      $x =~ s/_\w+/_VPRT/;
    }

    # Tags second person pronouns - ADDED "THOU", "THY", "THEE", "THYSELF" ELF: added nominal possessive pronoun (yours), added ur, ye and y' (for y'all).
    if ($x =~ /\byou_|\byour_|\byourself_|\byourselves_|\bthy_|\bthee_|\bthyself_|\bthou_|\byours_|\bur_|\bye_PRP|\by'_|\bthine_|\bya_PRP/i) {
      $x =~ s/_\w+/_SPP2/;
    }

    # Tags third person pronouns 
    # ELF: added themself in singular (cf. https://www.lexico.com/grammar/themselves-or-themself), added nominal possessive pronoun forms (hers, theirs), also added em_PRP for 'em.
    # ELF: Subdivided Biber's category into non-interactant plural and non-plural.
     if ($x =~ /\bthey_|\bthem_|\btheir_|\bthemselves_|\btheirs_|em_PRP/i) {
      $x =~ s/_\w+/_TPP3P/;
    }
    # Note that this variable cannot account for singular they except for the reflective form.
     if ($x =~ /\bhe_|\bshe_|\bher_|\bhers_|\bhim_|\bhis_|\bhimself_|\bherself_|\bthemself_/i) {
      $x =~ s/_\w+/_TPP3S/;
    }
    
    # Tags "can" modals 
    # ELF: added _MD onto all of these. And ca_MD which was missing for can't.
    if ($x =~ /\bcan_MD|\bca_MD/i) {
      $x =~ s/_\w+/_MDCA/;
    }
    
    # Tags "could" modals
    if ($x =~ /\bcould_MD/i) {
      $x =~ s/_\w+/_MDCO/;
    }

    # Tags necessity modals
    # ELF: added _MD onto all of these to increase precision.
    if ($x =~ /\bought_MD|\bshould_MD|\bmust_MD|\bneed_MD/i) {
      $x =~ s/_\w+/_MDNE/;
    }

    # Tags "may/might" modals
    # ELF: added _MD onto all of these to increase precision.
    if ($x =~ /\bmay_MD|\bmight_MD/i) {
      $x =~ s/_\w+/_MDMM/;
    }
    
    # Tags will/shall modals. 
    # ELF: New variable replacing Biber's PRMD.
    if ($x =~ /\bwill_MD|'ll_MD|\bshall_|\bsha_|\bwo_MD/i) {
      $x =~ s/_\w+/_MDWS/;
    }

    # Tags would as a modal. 
    # ELF: New variable replacing PRMD.
    if ($x =~ /\bwould_|'d_MD/i) {
      $x =~ s/_\w+/_MDWO/;
    }
    
    # ELF: tags activity verbs. 
    # Note that adding _P is important to capture verbs tagged as PEAS, PROG or_PASS.
    if ($x =~ /\b($vb_act)_V|\b($vb_act)_P/i) {
      $x =~ s/_(\w+)/_$1 ACT/;
    }
    
    # ELF: tags communication verbs. 
    # Note that adding _P is important to capture verbs tagged as PEAS, PROG or PASS.
    if ($x =~ /\b($vb_comm)_V|\b($vb_comm)_P/i) {
      $x =~ s/_(\w+)/_$1 COMM/;
    }
    
    # ELF: tags mental verbs (including the "no" in "I dunno" and "wa" in wanna). 
    # Note that adding _P is important to capture verbs tagged as PEAS, PROG or PASS.
    if ($x =~ /\b($vb_mental)_V|\b($vb_mental)_P|\bno_VB/i) {
      $x =~ s/_(\w+)/_$1 MENTAL/;
    }
    
    # ELF: tags causative verbs. 
    # Note that adding _P is important to capture verbs tagged as PEAS, PROG or PASS.
    if ($x =~ /\b($vb_cause)_V|\b($vb_cause)_P/i) {
      $x =~ s/_(\w+)/_$1 CAUSE/;
    }
    
    # ELF: tags occur verbs. 
    # Note that adding _P is important to capture verbs tagged as PEAS, PROG or PASS.
    if ($x =~ /\b($vb_occur)_V|\b($vb_occur)_P/i) {
      $x =~ s/_(\w+)/_$1 OCCUR/;
    }
    
    # ELF: tags existential verbs. 
    # Note that adding _P is important to capture verbs tagged as PEAS, PROG or PASS.
    if ($x =~ /\b($vb_exist)_V|\b($vb_exist)_P/i) {
      $x =~ s/_(\w+)/_$1 EXIST/;
    }
    
    # ELF: tags aspectual verbs. 
    # Note that adding _P is important to capture verbs tagged as PEAS, PROG or PASS.
    if ($x =~ /\b($vb_aspect)_V|\b($vb_aspect)_P/i) {
      $x =~ s/_(\w+)/_$1 ASPECT/;
    }
    
    # Tags verbal contractions
    if ($x =~ /'\w+_V|\bn't_XX0|'ll_|'d_/i) {
      $x =~ s/_(\w+)/_$1 CONT/;
    }
    
    # tags the remaining interjections and filled pauses. 
    # ELF: added variable
    # Note: it is important to keep this variable towards the end because some UH tags need to first be overridden by other variables such as politeness (please) and pragmatic markers (yes). 
    if ($x =~ /_UH/) {
      $x =~ s/_(\w+)/_FPUH/;
    }
      
    # ELF: added variable: tags adverbs of frequency (list from COBUILD p. 270).
    if ($x =~ /\busually_|\balways_|\bmainly_|\boften_|\bgenerally|\bnormally|\btraditionally|\bagain_|\bconstantly|\bcontinually|\bfrequently|\bever_|\bnever_|\binfrequently|\bintermittently|\boccasionally|\boftens_|\bperiodically|\brarely_|\bregularly|\brepeatedly|\bseldom|\bsometimes|\bsporadically/i) {
      $x =~ s/_(\w+)/_FREQ/;
    }
    
    # ELF: remove the TO category which was needed for the identification of other features put overlaps with VB
    #if ($x =~ /_TO/) {
     # $x =~ s/_(\w+)/_IN/;
    #}    
  }
  
    #---------------------------------------------------

	# Tags noun compounds 
	# ELF: New variable. Only works to reasonable degree of accuracy with "well-punctuated" (written) language, though.
	# Allows for the first noun to be a proper noun but not the second thus allowing for "Monday afternoon" and "Hollywood stars" but not "Barack Obama" and "L.A.". Also restricts to nouns with a minimum of two letters to avoid OCR errors (dots and images identified as individual letters and which are usually tagged as nouns) producing lots of NCOMP's.
	
  for ($j=0; $j<@word; $j++) {
	
	if ($word[$j] =~ /\b.{2,}_NN/ && $word[$j+1] =~ /\b(.{2,}_NN|.{2,}_NNS)\b/ && $word[$j] !~ /\NCOMP/) {
		$word[$j+1] =~ s/_(\w+)/_$1 NCOMP/;
    }
      
    # Tags total nouns by joining plurals together with singulars including of proper nouns.
    if ($word[$j] =~ /_NN|_NNS|_NNP|_NNPS/) {
      $word[$j] =~ s/_\w+/_NN/;
    }

  }


  return @word;
}


############################################################
## Obtain feature counts in table formats.

##   do_counts($prefix, $tagged_dir, $tokens_for_ttr);
sub do_counts {
  my ($prefix, $tagged_dir, $tokens_for_ttr) = @_;

  opendir(DIR, $tagged_dir) or die "Can't read directory $tagged_dir/: $!";
  my @filenames = grep {-f "$tagged_dir/$_"} readdir(DIR);
  close(DIR);
  my $n_files = @filenames;
  
  my @tokens = (); # tokens counts
  my %counts = (); # feature counts
  my %ttr_h = ();  # type/token ration (TTR) 
  my %lex_density = (); # for lexical density
  

  
  ## read each file and
  foreach my $i (0 .. $n_files - 1) {
    my $textname = $filenames[$i];

    {
      local $/ = undef ;
      open(FH, "$tagged_dir/$filenames[$i]") or die "Can't read tagged file $tagged_dir/$filenames[$i]: $!";
      $text = <FH>;
      close(FH);
    }

    $text =~ s/\n/ /g;  #converts end of line in space
    @word = split (/\s+/, $text);
    # The following line was contributed by Peter Uhrig to account for non-breaking spaces within tokens (UTF-8 C2 A0). It has not yet been sufficiently tested to be yet in use.
    #@word = split (/ +/, $text);
    @types = (); # SE: actually, these are the tokens (without tags)
    @functionwords = ();


    foreach $x (@word) {

# ELF: Corrected an error in the MAT which did NOT ignore punctuation in token count (although comments said it did). Also decided to remove possessive s's, symbols, filled pauses and interjections (FPUH) from this count.
      $tokens[$i]++;
      if ($x =~ /(_\s)|(\[\w+\])|(.+_\W+)|(-RRB-_-RRB-)|(-LRB-_-LRB-)|.+_SYM|_POS|_FPUH/) {  
        $tokens[$i]--;
      }
# EFL: Counting function words for lexical density
	  if ($x =~ /\b($function_words)_/i) {
	  	$functionwords[$i]++;
	  }
	  
# EFL: Counting total nouns for per 100 noun normalisation
	  if ($x =~ /_NN/) {
	  	$NTotal[$i]++;
	  }
	  
# EFL: Approximate counting of total finite verbs for the per 100 finite verb normalisation
	  if ($x =~ /_VPRT|_VBD|_VIMP|_MDCA|_MDCO|_MDMM|_MDNE|_MDWO|_MDWS/) {
	  	$VBTotal[$i]++;
	  }

# ELF: I've decided to exclude all of these for the word length variable (i.e., possessive s's, symbols, punctuation, brackets, filled pauses and interjections (FPUH)):
      if ($x !~ /(_\s)|(\[\w+\])|(.+_\W+)|(-RRB-_-RRB-)|(-LRB-_-LRB-)|.+_SYM|_POS|_FPUH/) { 
      
        my($wordl, $tag) = split (/_(?!_)/, $x, 2); #divides the word in tag and word
        $wordlength = length($wordl);
        $totalchar{$textname} = $totalchar{$textname} + $wordlength;
        push @types, $wordl; # prepares array for TTR
      }

# ELF: List of tags for which no counts will be returned:
	# Note: if interested in counts of punctuation marks, "|_\W+" should be deleted in this line:
      if ($x !~ /_LS|_\W+|_WP\b|_FW|_SYM|_MD\b/) {  
        $x =~ s/^.*_//; # removes the word and leaves just the tag
        $counts{$x}{$textname}++; # creates and then fills a hash: POStag => number of occurrences for the file considered
      }

    }
    
    $average_wl{$textname} = $totalchar{$textname} / $tokens[$i]; # average word length
    
    $lex_density{$textname} = ($tokens[$i] - $functionwords[$i]) / $tokens[$i]; # ELF: lexical density
    
    #$func{$textname} = -$functionwords[$i]; # ELF: For debugging
        
    for ($j=0; $j<$tokens_for_ttr; $j++) { # Calculates TTR
      last if $j >= @types; # Stops if text is shorter than specified TTR size
      $ttr_h{$textname}++;
      if (exists ($ttr{lc($types[$j])}{$textname})) {
        $ttr_h{$textname}--;
      } else {
        $ttr{lc($types[$j])}{$textname}++;
      }
    }
    $ttr_h{$textname} /= $j; # Computes ratio rather than type count in case text is shorter than TTR size

  }
  
  ############################################################
  
   ## Output 1: Compute raw feature counts and write to table <prefix>_rawcounts.tsv
   
  open(FH, "> ${prefix}_rawcounts.tsv") or die "Can't write file ${prefix}_rawcounts.tsv: $!";
  print FH join("\t", qw(Filename Words AWL TTR LD), sort keys %counts), "\n"; 

  foreach my $i (0 .. $n_files - 1) {
    my $textname = $filenames[$i];

    printf FH "%s\t%d\t%.4f\t%.6f\t%.6f", $textname, $tokens[$i], $average_wl{$textname}, $ttr_h{$textname}, $lex_density{$textname};
    
    foreach $x (sort keys %counts) { # prints the frequencies for each tag
      if (exists ($counts{$x}{$textname})) {
        $counts{$x}{$textname} = $counts{$x}{$textname} # ELF: No normalisation, raw counts only.
      } else { # If there are no instances of that tag in this file it prints zero
        $counts{$x}{$textname} = 0;
      }
      print FH "\t$counts{$x}{$textname}";
    }
    
    print FH "\n";
  }

  close(FH);
  
  ############################################################

   # Output 2: Compute simple relative feature counts and write to table <prefix>_normed_100words_counts.tsv
   
  open(FH, "> ${prefix}_normed_100words_counts.tsv") or die "Can't write file ${prefix}_normed_100words_counts.tsv: $!";
  print FH join("\t", qw(Filename Words AWL TTR LD), sort keys %counts), "\n"; 

  %normed100 = ();
  foreach my $i (0 .. $n_files - 1) {
    my $textname = $filenames[$i];

    printf FH "%s\t%d\t%.4f\t%.6f\t%.6f", $textname, $tokens[$i], $average_wl{$textname}, $ttr_h{$textname}, $lex_density{$textname};
    
    foreach $x (sort keys %counts) { # prints the frequencies for each tag
	  if (exists ($counts{$x}{$textname})) {
        $normed100{$x}{$textname} = sprintf "%.4f", $counts{$x}{$textname} / $tokens[$i] * 100; # ELF: Normalisation per 100 words, rounded off to 4 decimals
        
      } else { # If there are no instances of that tag in this file it prints zero
        $normed100{$x}{$textname} = 0;
      }
      print FH "\t$normed100{$x}{$textname}";
    }
    
    print FH "\n";
  }

  close(FH);
  
  ############################################################

   ## Output 3: Compute custom relative feature counts and write to table <prefix>normed_complex_counts.tsv
  
	# List of features to be normalised per 100 nouns:
   my @NNTnorm = ("DT", "JJAT", "POS", "NCOMP");
   	# Features to be normalised per 100 (very crudely defined) finite verbs:
   my @FVnorm = ("ACT", "ASPECT", "CAUSE", "COMM", "CUZ", "CC", "EXIST", "ELAB", "JJPR", "MENTAL", "OCCUR", "DOAUX", "QUTAG", "SPLIT", "STPR", "WHQU", "THSC", "WHSC", "CONT", "VBD", "VPRT", "PROG", "HGOT", "BEMA", "MDCA", "MDCO", "THATD", "THRC", "VIMP", "MDMM", "ABLE", "MDNE", "MDWS", "MDWO", "XX0", "PASS", "PGET", "VBG", "VBN", "PEAS", "GTO"); 
   # All other features should be normalised per 100 words:
   my %Wnorm = ();
   
 	foreach $all (sort keys %counts) {
	 	my $add = 0;
 		foreach $nn ( @NNTnorm ) {
	 		if ($nn eq $all){
 				$add = 1;
 			}
	 	} 
	 	foreach $fv ( @FVnorm ) {
			if ($fv eq $all){
				$add = 1;
			}
		}
		if ($add == 0){
			$Wnorm{$all} = $counts{$all};
		}
 	}


 ## Compute "complex" custom relative feature counts and write to table <prefix>_normed_complex_counts.tsv
   open(FH, "> ${prefix}_normed_complex_counts.tsv") or die "Can't write file ${prefix}_normed_complex_counts.tsv: $!";
   print FH join("\t", qw(Filename Words AWL TTR LD), @NNTnorm, @FVnorm, sort(keys %Wnorm)), "\n";
   
  foreach my $i (0 .. $n_files - 1) {
     my $textname = $filenames[$i];
 
     printf FH "%s\t%d\t%.4f\t%.6f\t%.6f", $textname, $tokens[$i], $average_wl{$textname}, $ttr_h{$textname}, $lex_density{$textname};
 		
 
	%NNTnormresults = ();
	%FVnormresults = ();
	%Wnormresults = ();

 	foreach $y (@NNTnorm) {
 		if (exists ($counts{$y}{$textname}) && $counts{$y}{$textname} > 0 && $NTotal[$i] > 0) {
 			$NNTnormresults{$y}{$textname} = sprintf "%.4f", ($counts{$y}{$textname}/$NTotal[$i]) * 100;
 		} else {
 			$NNTnormresults{$y}{$textname} = 0;
 		}
 		print FH "\t$NNTnormresults{$y}{$textname}";
 	} 
 	foreach $y (@FVnorm) {
 		if (exists ($counts{$y}{$textname}) && $counts{$y}{$textname} > 0 && $VBTotal[$i] > 0) {
 			$FVnormresults{$y}{$textname} = sprintf "%.4f", $counts{$y}{$textname}/$VBTotal[$i] * 100;
 		} else {
 			$FVnormresults{$y}{$textname} = 0;
 		}
 		print FH "\t$FVnormresults{$y}{$textname}";
 	} 
 	foreach $y (sort keys %Wnorm) {
 		if (exists ($counts{$y}{$textname}) && $counts{$y}{$textname} > 0) {
 			$Wnormresults{$y}{$textname} = sprintf "%.4f", $counts{$y}{$textname}/$tokens[$i] * 100;
 		} else {
 			$Wnormresults{$y}{$textname} = 0;
 		}
 		print FH "\t$Wnormresults{$y}{$textname}";
 	} 			
 	
     print FH "\n";
  }
 
   close(FH);  

}