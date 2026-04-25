library(dplyr)
library(tidyr)
library(stringr)

source("globals.r")


contest_outstacks_df = CONTEST_OUTSTACKS_DF %>% 
  left_join(OUTSTACK_DF, join_by(OutstackConditionId == Id)) %>%
  rename(OutstackConditionDescription = Description)

invalidContest_outstacks = contest_outstacks_df %>%
  filter(OutstackConditionDescription == "InvalidContest") # not used in 2022

marks_valid_df = MARKS_DF %>%
  anti_join(invalidContest_outstacks, join_by(SessionIdx == SessionId, ContestId == ContestId))

marks_unamb = marks_valid_df %>%
  # Ambiguous Marks
  filter(IsAmbiguous == 0) %>%
  # Unassignable Writeins
  filter(is.na(WriteinDensity) | WriteinDensity != 0)

# Eliminate Overvotes

overvotes = marks_unamb %>%
  group_by(SessionIdx, Rank, ContestId) %>%
  count() %>%
  filter(n > 1) %>%
  select(SessionIdx, Rank, ContestId)

no_overvotes = marks_unamb %>%
  anti_join(overvotes, join_by(SessionIdx == SessionIdx, 
                               ContestId == ContestId, 
                               Rank >= Rank))

marks_overvotes_identified = bind_rows(no_overvotes, 
                                       overvotes %>% 
                                         mutate(CandidateId = -1))

# Eliminate all but first occurrence of candidate
uniq_ranks = marks_overvotes_identified %>%
  group_by(SessionIdx, ContestId, CandidateId) %>%
  summarize(Rank = min(Rank), .groups = "drop")

mark_uniq_ranks = marks_overvotes_identified %>%
  inner_join(uniq_ranks, join_by(SessionIdx == SessionIdx, 
                                 ContestId == ContestId,
                                 CandidateId == CandidateId,
                                 Rank == Rank))

# Checking for any missing outstacks
# Only writeins
mark_uniq_ranks %>% 
  inner_join(MARK_OUTSTACKS_DF, join_by(SessionIdx == SessionIdx, 
                                   ContestId == ContestId, 
                                   MarksIdx == MarkIdx)) %>%
  group_by(OutstackConditionId) %>%
  count()

# 9 is OvervotedRanking, which means it has to be in a contest with rankings,
# i.e. candidates, not measures.
# 5 is Overvote. Specifically measures
mark_uniq_ranks %>%
  filter(is.na(MarksIdx)) %>%
  select(SessionIdx, ContestId, Rank) %>%
  anti_join(MARK_OUTSTACKS_DF %>% filter(OutstackConditionId %in% c(5,9)), 
            join_by(SessionIdx == SessionIdx, ContestId == ContestId)) 

contest_ids = sort(unlist(uniq_ranks %>% select(ContestId) %>% unique()))

uniq_contest_ranks_list = lapply(contest_ids, function(contest_id) uniq_ranks %>% filter(ContestId == contest_id))

get_candidate_name = function(candidate_id){
  if (is.na(candidate_id)){
    # Needs non-empty string because strsplit will not return a piece if final
    # character is a delimiter
    return(" ")
  } else if (candidate_id == -1){
    return("Overvote")
  } else if (candidate_id == -2){
    return("Exhausted")
  } else {
    candidate_description = CANDIDATE_DF[CANDIDATE_DF$Id == candidate_id,]$Description
    candidate_lname = strsplit(candidate_description, ",")[[1]][1]
    return(candidate_lname)
  }
}

get_candidate_names = function(candidate_ids, sep = ";"){
  if (all(is.na(candidate_ids))){
    return(paste0(c("Blank", rep(paste0(sep, " "), 
                                 length(candidate_ids) - 1)), 
                  collapse = ""))
  }
  candidate_names = sapply(candidate_ids,  get_candidate_name)
  candidate_names_string = paste(candidate_names, collapse = sep)
  return(candidate_names_string)
}

get_last_candidate = function(rankings_table){
  first_place_votes = rankings_table %>%
    filter(Rank_1 > 0) %>%
    group_by(Rank_1) %>%
    summarize(tot_votes = sum(tot_votes)) %>%
    arrange(tot_votes)
  last_candidate = first_place_votes$Rank_1[1]
  return(last_candidate)
}

reduce_candidates = function(summary_df, candidates_to_eliminate = NA,
                             candidates_to_keep = NA){
  if (identical(candidates_to_keep, NA) & 
      identical(candidates_to_eliminate, NA)){
    stop("One of candidates_to_keep or candidates_to_elimanate must be present")
  } else if (!identical(candidates_to_keep, NA) & 
             !identical(candidates_to_eliminate, NA)){
    stop("Only one of candidates_to_keep or candidates_to_eliminate may be
       present")
  }
  rank_values = unique(unlist(summary_df %>% 
                                select(starts_with("Rank"))))
  if (!identical(candidates_to_keep, NA)){
    rank_values_to_eliminate = rank_values[!(rank_values %in% candidates_to_keep) &
                                             !is.na(rank_values) &
                                             !(rank_values < 0)]
  } else {
    rank_values_to_eliminate = candidates_to_eliminate
  }
  # Mark exhausted ballots (but not blank ballots) as exhausted (-2)
  summary_df = summary_df %>%
    mutate(Rank_1 = case_when(if_any(starts_with("Rank"), 
                                     ~ (.x %in% rank_values_to_eliminate)) & 
                                if_all(starts_with("Rank"), 
                                       ~ is.na(.x) | 
                                         (.x %in% rank_values_to_eliminate)) ~ -2,
                              TRUE ~ Rank_1))
  summary_df = summary_df %>%
    mutate(across(starts_with("Rank"), 
                  ~ case_when((.x %in% rank_values_to_eliminate) ~ NA,
                              TRUE ~ .x)))
  
  rank_cols = grep("Rank", colnames(summary_df))
  # Shift rankings if necessary
  summary_df[,rank_cols] = as.data.frame(t(apply(summary_df[,rank_cols], 
                                                 1, 
                                                 function(row) c(row[!is.na(row)], 
                                                                 row[is.na(row)]))))
  summary_df = summary_df %>% 
    # Drop unused rank columns (expected to be at end)
    select(where(function(col) !all(is.na(col)))) %>%
    group_by(across(c(ends_with("Description"), 
                      starts_with("Rank")))) %>%
    summarize(tot_votes = sum(tot_votes), .groups = "drop")
  return(summary_df)
}

write_rankings_df = function(rankings_df, 
                                      contest_id, 
                                      location = c("HD", "Precinct"),
                                      file_mode = c("Top", "Candidates")){
  location = match.arg(location)
  file_mode = match.arg(file_mode)
  if (location == "HD"){
    location_description = "HouseDescription"
    location_suffix = "house_district"
  } else if (location == "Precinct"){
    location_description = "PrecinctPortionDescription"
    location_suffix = "Precinct"
  } else {
    stop("Invalid location argument")
  }
  colnames_rankings_df = colnames(rankings_df)
  rank_columns = grep("Rank", colnames_rankings_df)
  
  candidates_in_rankings = unique(unlist(rankings_df %>%
                                           select(starts_with("Rank"))))
  
  candidates_in_rankings = candidates_in_rankings[!is.na(candidates_in_rankings) &
                                                    candidates_in_rankings > 0]
  candidates_count = length(candidates_in_rankings)
  
  ranking_df_count = rankings_df %>%
    mutate(ranking_string = apply(rankings_df[,rank_columns], 1, get_candidate_names)) %>% 
    select(ranking_string, as.name(location_description), tot_votes) %>%
    pivot_wider(names_from = ranking_string, 
                values_from = tot_votes,
                values_fill = 0)
  
  if (file_mode == "Top"){
    ranking_df_count = ranking_df_count %>%
      select(order(colnames(ranking_df_count))) %>%
      relocate(as.name(location_description)) %>%
      relocate(starts_with("Blank"), starts_with("Exhausted"), starts_with("Overvote"), .after = last_col()) %>%
      arrange(!!location_description)
  }
  if (file_mode == "Candidates"){
   ranking_df_count = ranking_df_count %>%
      select(order(colnames(ranking_df_count))) %>%
      relocate(any_of(sort(sapply(candidates_in_rankings, get_candidate_name)))) %>%
      relocate(contains("Description"))
  }
  
  
  if (location == "Precinct"){
    ranking_df_count = ranking_df_count %>%
      rowwise() %>%
      mutate(DistrictWide = grepl("^District", PrecinctPortionDescription)) %>%
      mutate(Numeric = grepl("^\\d", PrecinctPortionDescription)) %>%
      mutate(District = ifelse(DistrictWide, str_split(PrecinctPortionDescription, "-")[[1]], NA)) %>%
      mutate(Subdistrict = ifelse(DistrictWide, trimws(str_split_1(PrecinctPortionDescription, "-")[2]), NA)) %>%
      arrange(desc(Numeric), desc(DistrictWide), District, Subdistrict) %>%
      select(-DistrictWide, -District, -Subdistrict, -Numeric)
  }
  
  ranking_headers = as.data.frame(sapply(colnames(ranking_df_count), 
                                         function(header) strsplit(header, ";")))
  ranking_headers[ranking_headers == " "] = ""
  colnames(ranking_headers) = colnames(ranking_df_count)
  ranking_df_count = rbind(ranking_df_count, 
                           c("Total", 
                             colSums(ranking_df_count[2:ncol(ranking_df_count)])))
  
  
  ranking_df_table = rbind(ranking_headers, ranking_df_count)
  num_rankings = nrow(ranking_headers)
  ranking_df_table[c(1:nrow(ranking_headers)),1] = c(1:num_rankings)
  
  year = 2022
  race_description = CONTEST_DF[CONTEST_DF$Id == contest_id,]$Description
  race_dir = paste0("../Summaries/", year, "/", gsub("[ .()/]", "", race_description), "/")
  
  if (!dir.exists(race_dir)){
    dir.create(race_dir)
  }
  
  if (file_mode == "Top"){
    file_name = paste0("top-", candidates_count, "-", location_suffix, ".csv")
  } else {
    candidates_in_rankings = CANDIDATE_DF$Id[CANDIDATE_DF$Id %in% candidates_in_rankings]
    candidate_names = get_candidate_names(candidates_in_rankings, sep = "_")
    candidate_names = str_remove_all(candidate_names, "/")
    candidate_names = str_remove_all(candidate_names, "-")
    file_name = paste0(sort(candidate_names), "-", location_suffix, ".csv")
  }
  file_location = paste0(race_dir, file_name)
  write.table(ranking_df_table, 
              file_location, 
              sep = ",", 
              col.names = FALSE, 
              row.names = FALSE) 
}

write_pairwise_results = function(rankings_by_location, contest_id, location = c("HD", "Precinct")){
  location = match.arg(location)
  contest_candidates_df = CANDIDATE_DF %>%
                            filter(ContestId == contest_id)
  wi_candidates = contest_candidates_df$Id[contest_candidates_df$Type == "WriteIn"]
  rankings_by_location = rankings_by_location %>%
                          mutate(across(starts_with("Rank"), ~ ifelse(.x %in% wi_candidates, NA, .x))) %>%
                          group_by(across(!tot_votes)) %>%
                          summarize(tot_votes = sum(tot_votes), .groups = "drop")
  
  candidates = contest_candidates_df %>%
                  filter(Type == "Regular") %>%
                  select(Id) %>%
                  unlist()
  
  if (length(candidates) > 2){
    for (i in 1:(length(candidates) - 1)){
      for (j in c(i + 1):length(candidates)){
        rankings_paired = reduce_candidates(rankings_by_location, 
                                            candidates_to_keep = c(candidates[i], candidates[j]))
        rankings_paired = rankings_paired %>% 
                            group_by(across(contains("Description")), Rank_1) %>%
                            summarize(tot_votes = sum(tot_votes), .groups = "drop")
        
        write_rankings_df(rankings_paired, contest_id, location, file_mode = "Candidates") 
      }
    }
  }
}

get_rankings_by_precinct = function(rankings_by_session){
  rankings_by_precinct = rankings_by_session %>% 
    left_join(SESSIONS_DF, join_by(SessionIdx == SessionIdx)) %>%
    left_join(PP_to_P_DF, join_by(Original_PrecinctPortionId == PrecinctPortionId)) %>%
    mutate(PrecinctPortionDescription = str_replace(PrecinctPortionDescription, "  Q", " Q")) %>%
    group_by(across(c(PrecinctPortionDescription, starts_with("Rank")))) %>%
    count() %>%
    ungroup() %>%
    rename(tot_votes = n) %>%
    arrange(PrecinctPortionDescription)
  return(rankings_by_precinct)
}

get_rankings_by_house_district = function(rankings_by_session){
  rankings_by_hd = rankings_by_session %>% 
    left_join(SESSIONS_DF, join_by(SessionIdx == SessionIdx)) %>%
    left_join(PP_to_HD_DF, join_by(Original_PrecinctPortionId == PrecinctPortionId))%>%
    group_by(across(c(HouseDescription, starts_with("Rank")))) %>%
    count() %>%
    ungroup() %>%
    rename(tot_votes = n) %>%
    arrange(HouseDescription)
  return(rankings_by_hd)
}

write_top_contest_results = function(rankings_by_location, contest_id, 
                                     location = c("HD", "Precinct")){
  location = match.arg(location)
  num_candidates = CANDIDATE_DF %>%
    filter(ContestId == contest_id) %>%
    nrow()
  
  rankings_table = rankings_by_location
  rankings_table = rankings_table %>%
    group_by_at(vars(matches("Description"), paste0("Rank_", c(1:(num_candidates - 1))))) %>%
    summarize(tot_votes = sum(tot_votes), .groups = "drop")

  write_rankings_df(rankings_table, contest_id, location)  
  
  candidates = CANDIDATE_DF %>% 
    filter(ContestId == contest_id, Type == "Regular") %>%
    select(Id) %>%
    unlist()
  num_candidates = length(candidates)
  if (num_candidates > 1){
    contest_candidates_df = CANDIDATE_DF %>%
      filter(ContestId == contest_id)
    wi_candidates = contest_candidates_df$Id[contest_candidates_df$Type == "WriteIn"]
    rankings_table = rankings_table %>%
      mutate(across(starts_with("Rank"), ~ ifelse(.x %in% wi_candidates, NA, .x))) %>%
      group_by(across(!tot_votes)) %>%
      summarize(tot_votes = sum(tot_votes), .groups = "drop")
  
    rankings_table = reduce_candidates(rankings_table, candidates_to_keep = candidates)
    num_candidates = length(candidates)
    for (candidates_remaining in c(num_candidates:2)){
      rankings_table = rankings_table %>%
                          group_by_at(vars(matches("Description"), paste0("Rank_", c(1:(candidates_remaining - 1))))) %>%
                          summarize(tot_votes = sum(tot_votes), .groups = "drop")
      write_rankings_df(rankings_table, contest_id, location) 
      if (candidates_remaining > 2){
        candidate_to_eliminate = get_last_candidate(rankings_table)
        rankings_table = reduce_candidates(rankings_table, candidate_to_eliminate)
      }
    } 
  }
}



get_candidate_by_session_rank = function(mark_sessions, rank_max, uniq_ranks,
                                         contest_id){
  candidate_by_session_rank = mark_sessions  
  for (ranking in c(1:rank_max)){
    candidate_by_session_rank = candidate_by_session_rank %>%
      left_join(uniq_ranks %>%
                  filter(Rank == ranking) %>%
                  select(SessionIdx, CandidateId),
                by = join_by(SessionIdx == SessionIdx)) %>%
      rename(!!paste0("Rank_", ranking) := CandidateId)
  }
  # Get sessions that had contest on ballot
  candidate_by_session_rank = SESSIONS_DF %>% 
    mutate(Original_BallotTypeId = as.integer(Original_BallotTypeId)) %>%
    inner_join(BALLOT_TYPE_CONTEST_DF %>% 
                 filter(ContestId == contest_id), 
               join_by(Original_BallotTypeId == BallotTypeId)) %>%
    select(SessionIdx) %>% 
    # Add sessions with no valid marks
    left_join(candidate_by_session_rank, join_by(SessionIdx)) %>%
    # Remove sessions from InvalidContests
    anti_join(CONTEST_OUTSTACKS_DF %>%
                filter(OutstackConditionId == 7,
                       ContestId == contest_id),
              join_by(SessionIdx==SessionId))
  return(candidate_by_session_rank)
}

remove_skips = function(candidate_by_session_rank, rank_max){
  if (rank_max > 2){
    for (ranking in c(3:rank_max)){
      candidate_by_session_rank = candidate_by_session_rank %>%
        mutate(!!paste0("Rank_", ranking) := ifelse(is.na(!!as.name(paste0("Rank_", ranking - 2))) & 
                                                      is.na(!!as.name(paste0("Rank_", ranking - 1))), 
                                                    NA, 
                                                    !!as.name(paste0("Rank_", ranking))))
    }
  }
  
  rankings_colnames = colnames(candidate_by_session_rank)
  
  rankings_by_session = as.data.frame(t(apply(candidate_by_session_rank, 
                                              1, 
                                              function(row) c(row[!is.na(row)], 
                                                              row[is.na(row)]))))
  
  colnames(rankings_by_session) = rankings_colnames
  return(rankings_by_session)
}

contest_ids_rcv = CONTEST_DF %>% 
                    filter(NumOfRanks > 0) %>% 
                    select(Id) %>% 
                    unlist()

#TODO don't hardcode
year = 2022
year_dir = paste0("../Summaries/", year)
if (!dir.exists(year_dir)){
  dir.create(year_dir)
}

for (location in c("HD", "Precinct")){
  for (contest_id in rev(contest_ids_rcv)){
    race_description = CONTEST_DF[CONTEST_DF$Id == contest_id,]$Description
    print(paste("Processing", race_description, "by", location))
    contest_uniq_ranks = uniq_contest_ranks_list[[which(contest_ids == contest_id)]]
    
    mark_sessions = mark_uniq_ranks %>%
      filter(ContestId == contest_id) %>%
      select(SessionIdx) %>%
      unique()
    
    rank_max = max(mark_uniq_ranks[mark_uniq_ranks$ContestId == contest_id,]$Rank)
    candidate_by_session_rank = get_candidate_by_session_rank(mark_sessions, 
                                                              #rank_max - 1,
                                                              rank_max,
                                                              contest_uniq_ranks,
                                                              contest_id)
    rankings_by_session = remove_skips(candidate_by_session_rank, 
                                       #rank_max - 1)
                                       rank_max)
    rank_cols = grep("Rank", colnames(rankings_by_session))
    rankings_by_session = rankings_by_session[,-rank_cols[length(rank_cols)]]
    
    if (location == "HD"){
      rankings_by_location = get_rankings_by_house_district(rankings_by_session)
    } else if (location == "Precinct"){
      rankings_by_location = get_rankings_by_precinct(rankings_by_session) 
    }
    write_top_contest_results(rankings_by_location, contest_id, location)
    write_pairwise_results(rankings_by_location, contest_id, location)
  }
}