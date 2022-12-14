library(jsonlite)

get_marks = function(session, race_id){
  original = session$Original
  cards = original$Cards[[1]]
  contests = cards$Contests
  race_index = which(lapply(contests, function(x) x$Id) == race_id)
  if (length(race_index) == 0){
    return(NULL)
  }
  else{
    race = contests[[race_index]]
    marks = race$Marks
    return(marks)
  }
}

is_mark_ambiguous = function(marks){
  return(sapply(marks, function(mark) mark$IsAmbiguous))
}

eliminate_ambiguous_marks = function(marks){
  return(marks[!is_mark_ambiguous(marks)])
}

is_mark_bad_writein = function(mark){
  if ("WriteinDensity" %in% attributes(mark)$names){
    return(mark$WriteinDensity == 0)
  } else {
    return(FALSE)
  }
}

eliminate_bad_writeins = function(marks){
  return(marks[!sapply(marks, is_mark_bad_writein)])
}

eliminate_overvotes = function(marks_list){
  if(length(marks_list) == 0){
    return(marks_list)
  }
  is_overvote = sapply(marks_list, function(rank_list) length(rank_list) > 1)
  overvotes = which(is_overvote)
  if (length(overvotes) > 0){
    first_overvote = min(overvotes)
    if(first_overvote == 1){
      return(list("Overvote"))
    } else {
      return_list = marks_list[1:(first_overvote - 1)]
      return_list[[first_overvote]] = "Overvote"
      return(return_list)
    }
  } else {
    return(marks_list)
  }
}

marks_to_list = function(marks){
  rslt_list = list()
  for (mark in marks){
    rank = mark$Rank
    c_id = mark$CandidateId
    if (length(rslt_list) < rank){
      rslt_list[[rank]] = c_id
    } else {
      rslt_list[[rank]] = c(rslt_list[[rank]], c_id)
    }
  }
  return(rslt_list)
}

eliminate_dup_candidates = function(marks){
  if(length(marks) == 0){
    return(marks)
  }
  c_duplicated = duplicated(marks)
  c_null = sapply(marks, function(x) is.null(x))
  ranks_to_remove = rev(which(c_duplicated & !c_null))
  for(rank in ranks_to_remove){
    marks[rank] = list(NULL)
  }
  return(marks)
}

eliminate_skips = function(marks){
  if (length(marks) == 0){
    return(NULL)
  }
  ranks = which(!sapply(marks, function(mark) is.null(mark)))
  gaps = diff(c(0, ranks))
  large_gaps = which(gaps >= 3)
  if (length(large_gaps) == 0){
    return(unlist(marks))
  }
  first_gap = large_gaps[1]
  if (first_gap == 1){
    return(NULL)
  } else {
    return(unlist(marks[ranks[1:(first_gap - 1)]]))
  }
}

get_ranking = function(session, race_id){
   marks = get_marks(session, race_id)
   unambiguous_marks = eliminate_ambiguous_marks(marks)
   good_marks = eliminate_bad_writeins(unambiguous_marks)
   marks_list = marks_to_list(good_marks)
   marks_no_over = eliminate_overvotes(marks_list)
   marks_no_dups = eliminate_dup_candidates(marks_no_over)
   marks_no_skips = eliminate_skips(marks_no_dups)
   return(marks_no_skips)
 }

get_precinct_portion = function(session){
  return(session$Original$PrecinctPortionId)
}

get_pp_desc = function(session){
  pp_id = get_precinct_portion(session)
  pp_desc = PP_DF[PP_DF$Id == pp_id,]$Description
  return(pp_desc)
}

get_hd = function(session){
  pp = get_precinct_portion(session)
  districts = DPPM_DF$DistrictId[DPPM_DF$PrecinctPortionId == pp]
  hd = DM_DF$Id[DM_DF$Id %in% districts & 
                         DM_DF$DistrictTypeId == HOUSE_ID]
  
  return(hd)
}

get_hd_desc = function(session){
  hd = get_hd(session)
  return(DM_DF$Description[DM_DF$Id == hd])
}

get_precinct_portion_ballots = function(precinct_portion_id, sessions){
  precinct_portions = lapply(sessions, function(x) get_precinct_portion(x))
  matching_session_ids = which(precinct_portions == precinct_portion_id)
  return(sessions[matching_session_ids])
}

get_last_place = function(df){
  first_place_names = unique(unlist(df[1,]))
  first_place_names = first_place_names[!(first_place_names %in% c("Blank", "Exhausted", "Overvote"))]
  num_ranked = length(first_place_names) - 1
  vote_rows = c((num_ranked + 1):nrow(df))
  first_votes_by_name = c()
  
  for (name in first_place_names){
    first_place_totals = df["Total",df[1,] == name]
    first_place_votes = sum(as.numeric(first_place_totals))
    first_votes_by_name[name] = first_place_votes #188524
  }
  eliminated_candidate = names(which.min(first_votes_by_name))
  return(eliminated_candidate)
  
}

eliminate_candidates = function(df, num_ranked, candidates_to_eliminate, is_write_in = FALSE){
  results_df = as.data.frame(c(0))[-1,-1]
  num_candidates_to_eliminate = length(candidates_to_eliminate)
  name_rows = c(1:(num_ranked - 1 - num_candidates_to_eliminate))
  vote_rows = c(num_ranked:nrow(df))
  
  for(i in c(ncol(df):1)){
    col_name_order = df[c(1:(num_ranked - 1)),i]
    non_elim_candidates = col_name_order[!(col_name_order %in% candidates_to_eliminate)]
    non_elim_candidates = non_elim_candidates[non_elim_candidates != ""]
    if(length(non_elim_candidates) == 0){
      if (is_write_in){
        non_elim_candidates = "Blank"
      } else {
        non_elim_candidates = "Exhausted"
      }
    }
    if(length(non_elim_candidates) >= num_ranked - num_candidates_to_eliminate){
      non_elim_candidates = non_elim_candidates[c(1:(num_ranked - num_candidates_to_eliminate - 1))]
    }
    num_non_elim = length(non_elim_candidates)
    pasted_names = paste(non_elim_candidates, collapse = ";")
    non_elim_candidates = c(non_elim_candidates, rep("", num_ranked - num_non_elim - num_candidates_to_eliminate - 1))
    if (pasted_names %in% names(results_df)){
      current_votes = results_df[vote_rows - num_candidates_to_eliminate, pasted_names]
      new_votes = df[vote_rows ,i]
      updated_votes = as.character(as.numeric(current_votes) + as.numeric(new_votes))
      results_df[vote_rows - num_candidates_to_eliminate, pasted_names] = updated_votes
      
    } else {
      results_df[name_rows, pasted_names] = non_elim_candidates
      results_df[vote_rows - num_candidates_to_eliminate, pasted_names] = df[vote_rows ,i]
    }
    
  }
  rownames(results_df) = rownames(df)[-c((num_ranked - num_candidates_to_eliminate):(num_ranked - 1))]
  results_df = results_df[,order(colnames(results_df))]
  results_df = cbind(results_df[,!(colnames(results_df) %in% c("Blank", "Exhausted", "Overvote"))], results_df[,colnames(results_df) %in% c("Blank", "Exhausted", "Overvote")])
  
  return(results_df)
}

eliminate_last_place = function(df, num_ranked){
  candidate_last = get_last_place(df)
  return(eliminate_candidates(df, num_ranked, candidate_last))
}

process_session_data = function(sessions, race_id, get_area_desc, race_candidates_df){
  num_candidates = nrow(race_candidates_df)
  race_candidate_ids = c(race_candidates_df$Id, "Overvote")
  race_candidate_names = c(race_candidates_df$Description, "Overvote")
  race_lnames = sapply(strsplit(race_candidate_names, ","), function(x) x[1])
  
  contest_district_id = contest_df[contest_df$Id == race_id,]$DistrictId
  contest_precinct_portions = DPPM_DF[DPPM_DF$DistrictId == contest_district_id,]$PrecinctPortionId
  contest_sessions = sessions[SESSIONS_PP %in% contest_precinct_portions]
  
  session_areas = sapply(contest_sessions, get_area_desc)
  area_descs = unique(session_areas)
  area_results = as.data.frame(c(0))[-1,-1]
  for (i in c(1:length(area_descs))){
    area_desc = area_descs[i]
    area_sessions = contest_sessions[session_areas == area_desc]
    area_rankings = lapply(area_sessions, function(x) get_ranking(x, race_id))
    has_ranking = sapply(area_rankings, length) > 0
    area_rankings[has_ranking] = lapply(area_rankings[has_ranking], function(x) x[1:min(length(x), num_candidates - 1)])
    area_ranking_names = lapply(area_rankings, function(x) sapply(x, function(y) race_lnames[y == race_candidate_ids]))
    rank_paste = sapply(area_ranking_names, function(x) paste(x, collapse = ";"))
    result_summary = table(rank_paste)
    names(result_summary)[names(result_summary) == ""] = "Blank"
    for (name in names(result_summary)){
      area_results[area_descs[i], name] = result_summary[name]
    }
  }
  area_results[is.na(area_results)] = 0
  totals = colSums(area_results[1:nrow(area_results),])
  area_results = area_results[sort(rownames(area_results)),]
  
  area_results["Total", ] = totals
  
  name_order = sapply(names(area_results), function(x) strsplit(x, ";"))
  max_names = max(sapply(name_order, length))
  name_df = matrix(, nrow = max_names, ncol = length(name_order))
  for(i in c(1:max_names)){
    name_df[i,] = unlist(sapply(name_order, function(x) x[i]))
  }
  name_df[is.na(name_df)] = ""
  colnames(name_df) = colnames(area_results)
  
  area_rank_results = rbind(name_df, area_results)
  area_rank_results = area_rank_results[,order(names(area_rank_results))]
  none_col = which(colnames(area_rank_results) == "Blank")
  if(length(none_col) > 0){
    area_rank_results = cbind(area_rank_results[,-c(none_col),],
                            area_rank_results[,"Blank"])
    colnames(area_rank_results)[ncol(area_rank_results)] = "Blank"
  }
  
  
  return(area_rank_results)
}

cvr_dir = "../Data/CVR_Export/"

cvr_export_file = paste0(cvr_dir, "CvrExport.RData")
if (file.exists(cvr_export_file)){
  cvr_data = readRDS(cvr_export_file)
} else {
  print("CVR combined file not found. Combining data now...")
  dir_files = list.files(cvr_dir)
  cvr_files = dir_files[grepl("CvrExport.*json", dir_files)]
  num_files = length(cvr_files)
  if(num_files == 0){
    stop("No CVR JSON files found!")
  }
  cvr_files = paste0(cvr_dir, cvr_files)
  print(paste0("Reading file 1/", num_files))
  cvr_data = jsonlite::read_json(cvr_files[1])
  if (length(cvr_files) > 1){
    for (i in c(2:length(cvr_files))){
      print(paste0("Reading file ", i, "/", num_files))
      cvr_file = cvr_files[i]
      cvr_data_section = jsonlite::read_json(cvr_file)
      cvr_data$Sessions = c(cvr_data$Sessions, cvr_data_section$Sessions)
    }
  }
  print("Saving combined file...")
  saveRDS(cvr_data, file = cvr_export_file)
  print("Saved!")
}

sessions = cvr_data$Sessions
SESSIONS_PP = sapply(sessions, get_precinct_portion)

year_index = regexpr("[[:digit:]]{4}", cvr_data$ElectionId)
year = substr(cvr_data$ElectionId, year_index, year_index + 3)

cm_file = paste0(cvr_dir, "CandidateManifest.json")
candidate_manifest = jsonlite::read_json(cm_file)$List
candidate_df = do.call(rbind.data.frame, candidate_manifest)

ppm_file = paste0(cvr_dir, "PrecinctPortionManifest.json")
ppm = jsonlite::read_json(ppm_file)$List
PP_DF = do.call(rbind.data.frame, ppm)

dppm_file = paste0(cvr_dir, "DistrictPrecinctPortionManifest.json")
dppm = jsonlite::read_json(dppm_file)$List 
DPPM_DF = do.call(rbind.data.frame, dppm)

dm_file = paste0(cvr_dir, "DistrictManifest.json")
dm = jsonlite::read_json(dm_file)$List 
DM_DF = do.call(rbind.data.frame, dm)

dtm_file = paste0(cvr_dir, "DistrictTypeManifest.json")
dtm = jsonlite::read_json(dtm_file)$List 
DTM_DF = do.call(rbind.data.frame, dtm)
HOUSE_ID = DTM_DF$Id[DTM_DF$Description == "State House"]

cm_file = paste0(cvr_dir, "ContestManifest.json")
contest_manifest = jsonlite::read_json(cm_file)$List
contest_df = do.call(rbind.data.frame, contest_manifest)
rcv_contests = contest_df[contest_df$NumOfRanks > 1,]

race_ids = rcv_contests$Id

cat_functions = c(get_pp_desc, get_hd_desc)

for(cat_function in cat_functions){
  for(race_id in race_ids){
    race_description = rcv_contests[rcv_contests$Id == race_id, ]$Description
    if (identical(cat_function, get_pp_desc)){
      cat_suffix = "precinct"
    } else {
      cat_suffix = "house_district"
    }
    print(paste("Processing", cat_suffix, "data for", race_description))
    
    race_dir = paste0("../Summaries/", year, "/", gsub("[ .()/]", "", race_description), "/")
    if (!dir.exists(race_dir)){
      dir.create(race_dir)
    }
    
    race_candidates_df = candidate_df[candidate_df$ContestId == race_id,]
    
    num_candidates = nrow(race_candidates_df)
    
    print("...aggregating data")
    area_results = process_session_data(sessions, 
                                        race_id, 
                                        cat_function,
                                        race_candidates_df)
    print("...RCV caculations")
    
    file_name = paste0("top-", num_candidates, "-", cat_suffix, ".csv")
    file_path = paste0(race_dir, file_name)
    write.table(area_results, sep = ",", file = file_path, col.names = FALSE)
    if (num_candidates > 2){
      area_results_wo_writein = eliminate_candidates(area_results, num_candidates, "Write-in", TRUE)
      table_to_write = area_results_wo_writein
      for (i in c((num_candidates - 1):2)){
        file_name = paste0("top-", i, "-", cat_suffix, ".csv")
        file_path = paste0(race_dir, file_name)
        write.table(table_to_write, sep = ",", file = file_path, col.names = FALSE)
        if (i != 2){
          table_to_write = eliminate_last_place(table_to_write, i)
        }
      }
      regular_candidates = race_candidates_df$Description[race_candidates_df$Type == "Regular"]
      if (length(regular_candidates) > 2){
        print("...head-to-head results")
        race_lnames = sapply(strsplit(regular_candidates, ","), function(x) x[1])
        for(candidate_1_idx in c(1:(length(race_lnames) - 1))){
          for(candidate_2_idx in c((candidate_1_idx+1):length(race_lnames))){
            candidates_to_eliminate = race_lnames[c(-candidate_1_idx, -candidate_2_idx)]
            table_to_write = eliminate_candidates(area_results_wo_writein, num_candidates - 1, candidates_to_eliminate)
            candidate_1_lname = gsub("/", "", race_lnames[candidate_1_idx])
            candidate_2_lname = gsub("/", "", race_lnames[candidate_2_idx])
            file_name = paste0(candidate_1_lname, "_", candidate_2_lname, "-", cat_suffix, ".csv")
            file_path = paste0(race_dir, "/", file_name)
            write.table(table_to_write, sep = ",", file = file_path, col.names = FALSE)
          }
        }
      }
    }
  }
}
