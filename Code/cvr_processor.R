source('cvr_parsing_functions.R')
cvr_dir = "../Data/CVR_Export/"
sessions_dir = paste0(cvr_dir, "sessions_dfs/")
if (!dir.exists(sessions_dir)){
  dir.create(sessions_dir)
}
contests_dir = paste0(cvr_dir, "contests_dfs/")
if (!dir.exists(contests_dir)){
  dir.create(contests_dir)
}

card_outstacks_dir = paste0(cvr_dir, "card_outstacks_dfs/")
if (!dir.exists(card_outstacks_dir)){
  dir.create(card_outstacks_dir)
}

marks_dir = paste0(cvr_dir, "marks_dfs/")
if (!dir.exists(marks_dir)){
  dir.create(marks_dir)
}

contest_outstacks_dir = paste0(cvr_dir, "contest_outstacks_dfs/")
if (!dir.exists(contest_outstacks_dir)){
  dir.create(contest_outstacks_dir)
}
mark_outstacks_dir = paste0(cvr_dir, "mark_outstacks_dfs/")
if (!dir.exists(mark_outstacks_dir)){
  dir.create(mark_outstacks_dir)
}

dir_files = list.files(cvr_dir)
cvr_files = paste0(cvr_dir, 
                   dir_files[grepl("CvrExport.*json", dir_files)])
num_files = length(cvr_files)
num_sessions_seen = 0L

for (i in c(1:num_files)){
  start_time = proc.time()[["elapsed"]]
  cvr_file = cvr_files[i]
  cvr_data_section = jsonlite::read_json(cvr_file)
  section_sessions = cvr_data_section$Sessions
  if (length(section_sessions) > 0){
    #Sessions_df
    sessions_section_df = create_sessions_df(section_sessions, num_sessions_seen)
    sessions_file = paste0(sessions_dir, "sessions_df_", i, ".rds")
    saveRDS(sessions_section_df, sessions_file)
    
    #Contests
    contests_df = bind_rows(lapply(c(1:length(section_sessions)), 
                                   function(idx) get_contests_df(idx + num_sessions_seen, 
                                                                 section_sessions[[idx]])))
    colnames(contests_df)= c("SessionIdx", "ContestId", "ManifestationId", 
                             "Undervotes", "Overvotes")
    contests_file = paste0(contests_dir, "contests_df_", i, ".rds")
    saveRDS(contests_df, contests_file)
    
    #Card_outstacks
    card_outstacks_df = bind_rows(lapply(c(1:length(section_sessions)), 
                                         function(session_idx) get_card_outstacks_df(session_idx + num_sessions_seen, 
                                                                                     section_sessions[[session_idx]])))
    colnames(card_outstacks_df) = c("SessionIdx", "OutstackConditionId")
    card_outstacks_file = paste0(card_outstacks_dir, "card_outstacks_df_", i, ".rds")
    saveRDS(card_outstacks_df, card_outstacks_file)
    
    #Marks
    marks_df = bind_rows(lapply(c(1:length(section_sessions)), function(idx) get_marks_df(idx + num_sessions_seen, section_sessions[[idx]])))
    colnames(marks_df) = c("SessionIdx", "ContestId", "MarksIdx", "CandidateId", "ManifestationId",
                           "PartyId", "Rank", "WriteinIndex", "MarkDensity",
                           "WriteinDensity", "IsAmbiguous", "IsVote")
    marks_file = paste0(marks_dir, "marks_df_", i, ".rds")
    saveRDS(marks_df, marks_file)
    
    #Contest_outstacks
    contest_outstacks_df = bind_rows(lapply(c(1:length(section_sessions)), 
                                            function(idx) get_contest_outstacks_df(idx + num_sessions_seen, section_sessions[[idx]])))
    colnames(contest_outstacks_df) = c("SessionId", "ContestId", "OutstackConditionId")
    
    contest_outstacks_file = paste0(contest_outstacks_dir, "contest_outstacks_df_", i, ".rds")
    saveRDS(contest_outstacks_df, contest_outstacks_file)
    
    #mark_outstacks
    mark_outstacks_df = bind_rows(lapply(c(1:length(section_sessions)), function(session_idx) get_session_mark_outstacks(num_sessions_seen + session_idx, section_sessions[[session_idx]])))
    colnames(mark_outstacks_df) = c("SessionIdx", "ContestId", "MarkIdx", "OutstackConditionId")
    mark_outstacks_file = paste0(mark_outstacks_dir, "mark_outstacks_df_", i, ".rds")
    saveRDS(mark_outstacks_df, mark_outstacks_file)
    
    num_sessions_seen = num_sessions_seen + length(section_sessions)
  }
  end_time = proc.time()[["elapsed"]]
  tot_time = end_time - start_time
  print(paste('i = ', i, ": elapsed_time = ", round(tot_time, digits = 2), sep=""))
  
}

data_pieces = c("sessions_df",
                "contests_df",
                "card_outstacks_df",
                "marks_df",
                "contest_outstacks_df",
                "mark_outstacks_df")

for(data_piece in data_pieces){
  print(data_piece)
  data_piece_df_list = vector(mode = 'list', length = num_files)
  for (i in c(1:num_files)){
    file_name = paste0(cvr_dir, data_piece, "s/", data_piece, "_", i, ".rds")
    if (file.exists(file_name)){
      data_piece_df_list[[i]] = readRDS(file_name)
    }
    print(i)
  }
  data_piece_df = bind_rows(data_piece_df_list)
  saveRDS(data_piece_df, paste0(cvr_dir, data_piece, ".rdata"))
}
