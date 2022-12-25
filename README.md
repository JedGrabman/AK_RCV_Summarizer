# Alaska Ranked Choice Vote Summarizer
## Disclaimer
This project is not affiliated with the State of Alaska and the summaries provided here are not used for any official purposes. These summaries may contain errors. For official data, please refer to [Election Results page on the Alaska Division of Elections website](https://www.elections.alaska.gov/election-results/).

## Ranked Choice Voting
In 2020, Alaska voters approved a new voting system, which includes a new primary system and ranked choice voting (RCV) in general elections. Under this system, up to 4 candidates may advance from the primary to the general election and voters may rank these candidates as their 1st choice, 2nd choice and so on. Please refer to the [Alaska Division of Elections's page on RCV](https://www.elections.alaska.gov/RCV.php) for a general overview on how this is implemented in Alaska.

## Summaries
This project generates precinct-level and house district-level summaries of voter preferences for each race. Within the `Results > 2022` folder, there is a folder for each race. Each race folder has a number of .CSV files, named as `Top-{n}-{division}`, where n = The number of remaining candidates and division is either "precinct" or "house-district". Additionally, there are head-to-head .CSV files for every pair of candidates in a race, named `{candidate1}_{candidate2}`. Please note that the data does not exactly follow the format used by the Alaska Division of Elections and may contain errors. Please review the "Accuracy" section for more details on known issues.

## Tabulating Ballots
The Alaska Division of Elections releases a *Cast Vote Record* (CVR) following each election. 
>The Cast Vote Record (CVR) contains the votes and rankings on all the primary/special general ballots that were scanned. It does not include ballots that were only counted by hand...
>The CVR is a JSON file, used by the ranked-choice software to tabulate the results. The CVR is not tabulation, it is a record of ballots.

It is necessary to closely look at CVR data, public statements by the Alaska Division of Elections, and official results of elections to determine how to tabulate summaries from the votes listed in the CVR data.

### Digital Representation of Ballots
As mentioned above, the CVR stores data in JSON format. The bulk of the data in the CVR is the `Sessions` array, where each entry is roughly the equivalent of a ballot. Within each Session, is a `Contests` object, where contest represents a specific election/race, and identified by a `ContestId`. Within each `Contest`, there is a `Marks` object, representing how the voter filled out the ballot for that `Contest`.

For each race, a voter is provided with a grid of bubbles to fill out to represent their preferences. Each row of the grid is labeled with a candidate's name, while each column is labeled "1st choice", "2nd choice" and so on. Thus, a voter may indicate that a candidate is their 1st choice by filling in the bubble in the candidate's row and the 1st choice column (and so on for their subsequent choices).

Within the `Contest` object, these filled-in bubbles are represented in the `Marks` array. Each `Mark` includes the following values (as well as some additional fields):  
* `CandidateId`: A numeric id representing the candidate the vote is for
* `Rank`: The numeric value of the ranking assigned the candidate (i.e. `2` if the candidate was marked as the 2nd choice.)
* `MarkDensity`: An integer from 0-100, presumably representing the percentage of the oval that was filled in.
* `IsAmbiguous`: `TRUE` or `FALSE`. Denotes whether the marking is ambiguous. This value appears to be `TRUE` whenever 0 < `MarkDensity` < 25 and `FALSE` otherwise.
* `WriteinDensity`: Only present if the vote is for a write-in candidate. Integer from 0-100, representing the "percentage that write-in area was filled in."

Note that the `Marks` represent what a voter filled in, which may include invalid selections, such as selecting multiple candidates for the same ranking or the same candidate for multiple rankings.

## Procedure for Determining Voter Preferences
Through examination of statements by the Alaska Division of Elections and comparison to official election results, I believe the procedure for moving for converting from the `Marks` object to an official judgment of the voters preferences is as follows:

1.) Eliminate ambiguous marks. Any `Mark` that has `IsAmbiguous` set to `TRUE` is discarded and has no effect on tabulation  
2.) Eliminate marks for write-in votes with a `WriteinDensity` of 0. These votes are in a row for a write-in vote, but have no candidate written in, so they would be impossible to assign.
3.) Eliminate overvotes. If a voter marks that they have an equal preference for 2 voters, then those marks and any subsequent marks are discarded. 
* **Example:** A voter ranks candidates A, B, C and D as their 1st, 2nd, 2nd and 3rd choice respectively. Because both B & C were both ranked 2nd, this is an overvote, and those marks are discarded. Additionally, the 3rd choice vote for D is also discarded, as it is subsequent to an overvote. The 1st choice vote for A is retained, because it was made before the overvote, not after it.

4.) Eliminate all but the 1st occurrence of a candidate. If a voter lists the same candidate multiple times, only the earliest ranking is retained. 
* **Example:** A voter ranks candidate A as their 1st choice and candidate B as their 2nd and 3rd choice. The `Mark` representing candidate B as the voters 2nd choice is retained, because it is the voter's earliest selection for candidate B. However, the `Mark` representing candidate B as the voters 3rd choice is discarded.

5.) If the difference between two consecutive ranks is 3 or greater, eliminate all marks after the gap. 
* **Example:** If a voter ranks candidate A as 1st, B as 4th and C as 5th, there is a gap of 3 rankings between A and B. Thus, the `Mark` for B is discarded, as is the `Mark` for C, as that selection is also after the gap.

6.) Remove any gaps that remain, retaining the relative order of the candidates. 
* **Example:** If a voter ranks candidate A 1st, B 3rd and has no candidate ranked 2nd, then B will be treated as though it were the voter's 2nd choice.

Note that if a `Mark` is discarded in an earlier step, it is not present to have an impact in a later step. For example, a voter may rank candidate A as their 1st, 2nd and 3rd choice, while ranking B as their 4th choice. In this case, the `Mark`s for candidate A being the voters 2nd and 3rd choice are discarded in step 3. Thus, at step 4, there is now a gap of 3 between the voters 1st choice for A and 4th choice for B. This leads to the 4th choice vote for B also being discarded.
### Handling Write-In votes
While the CVR indicates when a vote is for a write-in candidate, it does not indicate who was written in. The Alaska Division of Elections only goes through the process of determining write-in names if there are a sufficient number of write-in votes. Otherwise, all write-in candidates are considered defeated and their votes transfer to the voter's next preference (if any) before the 1st round of tabulation. A ballot that contains only a vote for a write-in candidate will be considered blank. As of December 2022, there has never been enough write-in votes in an Alaska RCV race to require the Alaska Division of Elections to manually determine which candidates had been written in. Therefore, we do not have the data for how that situation would be handled in the CVR, so the Summarizer currently assumes all write-in candidates are defeated before any other candidate.

### Accuracy
Summarizing the 2022 Senate Election using the previous algorithm and comparing them to the [official results](https://www.elections.alaska.gov/results/22GENR/US%20SEN.pdf) yielded the following:

1st Choice Results|Chesbro|Kelley|Murkowski|Tshibaka|Blanks|Overvotes
--|--:|--:|--:|--:|--:|--:
Actual|28,233|8,575|114,118|112,101|3271|499
Generated|28,232|8,575|114,118|112,096|3,273|503
Error|-1|0|0|-5|+2|+4

Transfers (Round 1 -> 2)|Kelley -> Chesbro|Kelley -> Murkowski|Kelley -> Tshibaka|Kelley -> Exhausted|Kelley -> Overvote
--|--:|--:|--:|--:|--:
Actual|901|1,641|3,209|2,806|18
Generated|900|1,641|3,210|2,806|18
Error|-1|0|+1|0|0

Transfers (Round 2 -> 3)|Chesbro -> Murkowski|Chesbro -> Tshibaka|Chesbro -> Exhausted|Chesbro -> Overvote
--|--:|--:|--:|--:
Actual|20,571|2,224|6,301|38
Generated|20,571|2,222|6,301|38
Error|0|-2|0|0

## Notes for Developers
If you wish to use the code directly, you'll need to download the CVR from the [Alaska Division of Elections](https://www.elections.alaska.gov/election-results/e/?id=22genr), unzip the file and add it to the directory, then update the value of `cvr_dir` in `rvc_processor.R` before running the file.

This project was developed with the top priority of making summary data available shortly after the release of the 2022 CVR data. As such, things like code clarity, documentation, efficiency and usability were not prioritized. As an open-source project, users are welcome to use the code as it is now, but should be aware that there may be substantial (i.e breaking) updates to the codebase shortly.
