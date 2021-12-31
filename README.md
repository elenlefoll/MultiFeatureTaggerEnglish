# The Multi-Feature Tagger of English (MFTE) v.3.0

The Multi-Feature Tagger of English (hereafter: the MFTE) is an automatic tagger for the analysis of situational variation in standard written and spoken general English. The MFTE was originally developed for use in multi-feature/multi-dimensional analysis (MDA; Biber 1984; 1988; 1995; Conrad & Biber 2013), a widely used framework first developed by Douglas Biber in the late 1980s. In short, MDA is based on the theoretical assumption that register-based variation can be observed as differences in patterns of co-occurring lexico-grammatical features, which result from texts having register-specific communicative goals and contexts of use.

The MFTE was originally based on a cross-platform version of [Andrea Nini’s Multidimensional Analysis Tagger (MAT)](https://github.com/andreanini/multidimensionalanalysistagger), which is, itself, an open-source replication of the Biber Tagger (1988). Like the MAT, it is available under a [GPL-3.0 License](/LICENSE) and requires the installation of the Stanford Tagger (see below). 

## Installation

1. Ensure that `perl5` is installed. If you work on a MacOS or another Unix-based system, it is likely already installed by default. Open a Terminal application and run `perl -v` to find out which version you have. If perl5 is not available, or if you work on Windows, follow the instructions here to install perl on your machine: https://www.perl.org/get.html

2. Install the `Stanford Tagger` in a dedicated folder. Information on the Stanford Tagger and how to install it can be obtained from: http://nlp.stanford.edu/software/tagger.shtml. The MFTE v.3.0 was built and evaluated on the ```stanford-postagger-2018-10-16/models/english-bidirectional-distsim.tagger``` but, in theory, any other English version of the Stanford Tagger could be used. If you are using a different version/model, change line 83 in `MFTE_3.0.pl` script to link to the version you have installed and intend to use.

3. Place `MFTE_3.0.pl` in the same folder as the Stanford Tagger.

Note that the MFTE was formally evaluated on perl 5, version 22, subversion 1 (v5.22.1) built for `x86_64-linux-gnu-thread-multi`. It was additionally tested on perl 5, version 30, subversion 2 (v5.30.2) built for `darwin-thread-multi-2level`.

## Usage

Navigate to the folder with the MFTE and the Stanford Tagger and run the `MFTE_3.0.pl` perl script from a terminal with the following command:

```
perl MFTE_3.0.pl input_txt/ tagged_txt/ prefix [TTRsize]
```

where:
- ```input_txt``` stands for the folder (path) containing the text files (in UFT-8) of the corpus to be tagged. Note that the folder ```input_txt``` must contain the corpus texts as separate files in plain text format (```.txt```) and ```UTF-8``` encoding.  All files in the folder will be processed, regardless of their extension.  
- ```tagged_txt``` stands for the folder (path) to be created by the programme to place the tagged text files.
- ```prefix``` stands for the prefix of the names of the three tables that will be output by the programme (see below).
- ```[TTRsize]``` is an optional parameter that defines how many words are used to calculate the type/token ratio (TTR) variable. It should be less than the shortest text in the corpus. If no value is entered the default is 400, as in Biber (1988).

e.g.:
```
perl MFTE_3.0.pl corpus/ corpus_MFTE_tagged/ MFTE_3.0 200
```

The above command will tag all the files of the folder `corpus`, save tagged versions of the texts (in vertical format) in a new folder called `corpus_MFTE_tagged` and create three tables of counts called ```MFTE_3.0_normed_complex_counts.tsv```, ```MFTE_3.0_normed_100words_counts.tsv``` and ```MFTE_3.0_raw_counts.tvs```. The type/token ratio feature will be calculated on the basis of the first 200 words of each text.

## Output

Tagged texts are stored under the same names in the folder ```tagged_txt/```.

Feature counts are extracted as TAB-separated tables. Each row corresponds to a text file from the corpus tagged and each column corresponds to a linguistic feature. The MFTE outputs three different tables of feature counts:
1.	```[prefix]_normed_complex_counts.tsv```            Normalised feature frequencies calculated on the basis of linguistically meaningful normalisation baselines (as listed in the fifth column of the List of Features)
2.	```[prefix]_normed_100words_counts.tsv```            Feature frequencies normalised to 100 words
3.	```[prefix]_raw_counts.tvs```                         Raw (unnormalised) feature counts

Note that the MFTE only tags and computes count tallies of all the features. It does not compute perform the multi-variate analysis itself. R scripts to carry out MDA analysis using EFA and PCA on the basis of the outputs of the MFTE will soon be added to this repository.

## Documentation

The MFTE tags over 70 features. The [List of Features](tables/ListFullMDAFeatures_v3.0.pdf) presents a tabular overview of these with examples and a brief explanation of each feature's operationalisation.

[Introducing the MFTE](/Introducing_the_MFTE_v3.0.pdf) is a 50-page document based on revised, selected chapters from an M.Sc. thesis submitted for the degree of Master of Science in Cognitive Science at the Institute of Cognitive Science, Osnabrück University (Germany) on 5 November 2021. It outlines the steps involved in the development of the MFTE. Section 2.1 outlines its specifications, which were drawn up on the basis of the features needed to carry out MDA and taking account of the advantages and limitations of existing taggers (see Le Foll 2021b: chap. 3). The following sections explain the methodological decisions involved in the selection of the features to be identified by the MFTE (2.2), the details of the regular expressions used to identify these features (2.3) and the procedure for normalising the feature counts (2.4). Section 2.5 describes the outputs of the tagger. Chapter 3 presents the method and results of an evaluation of the accuracy of the MFTE. It reports the results of comparisons of the tags assigned by the MFTE and by two human annotators to calculate precision and recall rates for each linguistic feature across a range of contrasting text registers. The [data](data) and [code](code/TaggerTestResults.Rmd) used to analyse the evaluation results are also available in this repository.

### Acknowledgments

I would like to thank Peter Uhrig and Michael Franke for supervising my M.Sc. thesis on the development and evaluation of the MFTE. Many thanks to Andrea Nini for releasing the MAT under an open-source licence. Heartfelt thanks also go to Stefanie Evert, Muhammad Shakir, and Luke Tudge who contributed advice and code in various ways (see comments in code for details) and to Larissa Goulart for her insights into the Biber Tagger. Finally, I would also like to thank Dirk Siepmann for supporting this project. 

### Citation

Please cite the MFTE as: 
Le Foll, Elen (2021). A Multi-Feature Tagger of English (MFTE). Software v.3.0. 
Available under a GPL-3.0 License on: https://github.com/elenlefoll/MultiFeatureTaggerEnglish

Please also cite the Stanford Tagger for English [http://nlp.stanford.edu/software/tagger.shtml]:
Kristina Toutanova, Dan Klein, Christopher Manning, & Yoram Singer (2003). Feature-Rich Part-of-Speech Tagging with a Cyclic Dependency Network. In Proceedings of HLT-NAACL 2003: pp. 252-259. 

### References

Biber, Douglas (1984). A model of textual relations within the written and spoken modes. University of Southern California. Unpublished PhD thesis.

Biber, Douglas (1988). Variation across speech and writing. Cambridge: Cambridge University Press. 

Biber, Douglas (1995). Dimensions of Register Variation. Cambridge, UK: Cambridge University Press.

Conrad, Susan & Douglas Biber (eds.) (2013). Variation in English: Multi-Dimensional Studies (Studies in Language and Linguistics). New York: Routledge.

Le Foll, Elen (2021). A New Tagger for the Multi-Dimensional Analysis of Register Variation in English. Osnabrück University: Institute of Cognitive Science Unpublished M.Sc. thesis.

Nini, Andrea (2014). Multidimensional Analysis Tagger (MAT). http://sites.google.com/site/multidimensionaltagger.

Nini, Andrea (2019). The Muli-Dimensional Analysis Tagger. In Berber Sardinha, T. & Veirano Pinto M. (eds), Multi-Dimensional Analysis: Research Methods and Current Issues, 67-94, London; New York: Bloomsbury Academic.

Toutanova, Kristina, Dan Klein, Christopher D Manning & Yoram Singer (2003). Feature-rich part-of-speech tagging with a cyclic dependency network. In, 173–180. Association for Computational Linguistics.
