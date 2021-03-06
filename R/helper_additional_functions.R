################################################################################
# Author: Ben Baldwin, Sebastian Carl
# Stlyeguide: styler::tidyverse_style()
################################################################################

#' Clean Play by Play Data
#'
#' @param pbp is a Data frame of play-by-play data scraped using \code{\link{fast_scraper}}.
#' @details Build columns that capture what happens on all plays, including
#' penalties, using string extraction from play description.
#' Loosely based on Ben's nflfastR guide (\url{https://mrcaseb.github.io/nflfastR/articles/beginners_guide.html})
#' but updated to work with the RS data, which has a different player format in
#' the play description; e.g. 24-M.Lynch instead of M.Lynch.
#' The function also standardizes team abbreviations so that, for example,
#' the Chargers are always represented by 'LAC' regardless of which year it was.
#' The function also standardizes player IDs for players appearing in both the
#' older era (1999-2010) and the new era (2011+).
#' @return The input Data Frame of the paramter 'pbp' with the following columns
#' added:
#' \describe{
#' \item{success}{Binary indicator wheter epa > 0 in the given play. }
#' \item{passer}{Name of the dropback player (scrambles included) including plays with penalties.}
#' \item{passer_jersey_number}{Jersey number of the passer.}
#' \item{rusher}{Name of the rusher (no scrambles) including plays with penalties.}
#' \item{rusher_jersey_number}{Jersey number of the rusher.}
#' \item{receiver}{Name of the receiver including plays with penalties.}
#' \item{receiver_jersey_number}{Jersey number of the receiver.}
#' \item{pass}{Binary indicator if the play was a pass play (sacks and scrambles included).}
#' \item{rush}{Binary indicator if the play was a rushing play.}
#' \item{special}{Binary indicator if the play was a special teams play.}
#' \item{first_down}{Binary indicator if the play ended in a first down.}
#' \item{aborted_play}{Binary indicator if the play description indicates "Aborted".}
#' \item{play}{Binary indicator: 1 if the play was a 'normal' play (including penalties), 0 otherwise.}
#' \item{passer_id}{ID of the player in the 'passer' column (NOTE: ids vary pre and post 2011 but are consistent for each player. Please see details for further information)}
#' \item{rusher_id}{ID of the player in the 'rusher' column (NOTE: ids vary pre and post 2011 but are consistent for each player. Please see details for further information)}
#' \item{receiver_id}{ID of the player in the 'receiver' column (NOTE: ids vary pre and post 2011 but are consistent for each player. Please see details for further information)}
#' \item{name}{Name of the 'passer' if it is not 'NA', or name of the 'rusher' otherwise.}
#' \item{jersey_number}{Jersey number of the player listed in the 'name' column.}
#' \item{id}{ID of the player in the 'name' column (NOTE: ids vary pre and post 2011 but are consistent for each player. Please see details for further information)}
#' \item{qb_epa}{Gives QB credit for EPA for up to the point where a receiver lost a fumble after a completed catch and makes EPA work more like passing yards on plays with fumbles.}
#' }
#' @export
#' @import dplyr
#' @importFrom stringr str_detect str_extract str_replace_all
#' @importFrom glue glue
#' @importFrom rlang .data
#' @importFrom tidyselect any_of
clean_pbp <- function(pbp) {
  message('Cleaning up play-by-play. If you run this with a lot of seasons this could take a few minutes.')

  # Load id map to standardize player ids for players that were active before 2011
  # and in or after 2011 meaning they appear with old gsis_ids and new ids
  legacy_id_map <- readRDS(url("https://github.com/guga31bb/nflfastR-data/blob/master/roster-data/legacy_id_map.rds?raw=true"))

  # drop existing values of clean_pbp
  pbp <- pbp %>% dplyr::select(-tidyselect::any_of(drop.cols))

  r <- pbp %>%
    dplyr::mutate(
      #get rid of extraneous spaces that mess with player name finding
      #if there is a space or dash, and then a capital letter, and then a period, and then a space, take out the space
      desc = stringr::str_replace_all(.data$desc, "(((\\s)|(\\-))[A-Z]\\.)\\s+", "\\1"),
      success = dplyr::if_else(is.na(.data$epa), NA_real_, dplyr::if_else(.data$epa > 0, 1, 0)),
      passer = stringr::str_extract(.data$desc, glue::glue('{big_parser}{pass_finder}')),
      passer_jersey_number = stringr::str_extract(stringr::str_extract(.data$desc, glue::glue('{number_parser}{big_parser}{pass_finder}')), "[:digit:]*") %>% as.integer(),
      rusher = stringr::str_extract(.data$desc, glue::glue('{big_parser}{rush_finder}')),
      rusher_jersey_number = stringr::str_extract(stringr::str_extract(.data$desc, glue::glue('{number_parser}{big_parser}{rush_finder}')), "[:digit:]*") %>% as.integer(),
      #get rusher_player_name as a measure of last resort
      #finds things like aborted snaps and "F.Last to NYG 44."
      rusher = dplyr::if_else(
        is.na(.data$rusher) & is.na(.data$passer) & !is.na(.data$rusher_player_name), .data$rusher_player_name, .data$rusher
      ),
      receiver = stringr::str_extract(.data$desc, glue::glue('{receiver_finder}{big_parser}')),
      receiver_jersey_number = stringr::str_extract(stringr::str_extract(.data$desc, glue::glue('{receiver_number}{big_parser}')), "[:digit:]*") %>% as.integer(),
      #overwrite all these weird plays messing with the parser
      receiver = dplyr::case_when(
        stringr::str_detect(.data$desc, glue::glue('{abnormal_play}')) ~ .data$receiver_player_name,
        TRUE ~ .data$receiver
      ),
      rusher = dplyr::case_when(
        stringr::str_detect(.data$desc, glue::glue('{abnormal_play}')) ~ .data$rusher_player_name,
        TRUE ~ .data$rusher
      ),
      passer = dplyr::case_when(
        stringr::str_detect(.data$desc, glue::glue('{abnormal_play}')) ~ .data$passer_player_name,
        TRUE ~ .data$passer
      ),
      #finally, for rusher, if there was already a passer (eg from scramble), set rusher to NA
      rusher = dplyr::if_else(
        !is.na(.data$passer), NA_character_, .data$rusher
      ),
      #if no pass is thrown, there shouldn't be a receiver
      receiver = dplyr::if_else(
        stringr::str_detect(.data$desc, ' pass'), .data$receiver, NA_character_
      ),
      #if there's a pass, sack, or scramble, it's a pass play
      pass = dplyr::if_else(stringr::str_detect(.data$desc, "( pass)|(sacked)|(scramble)"), 1, 0),
      #if there's a rusher and it wasn't a QB kneel or pass play, it's a run play
      rush = dplyr::if_else(!is.na(.data$rusher) & .data$qb_kneel == 0 & .data$pass == 0, 1, 0),
      #fix some common QBs with inconsistent names
      passer = dplyr::case_when(
        passer == "Jos.Allen" ~ "J.Allen",
        passer == "Alex Smith" | passer == "Ale.Smith" ~ "A.Smith",
        passer == "Ryan" & .data$posteam == "ATL" ~ "M.Ryan",
        passer == "Tr.Brown" ~ "T.Brown",
        passer == "Sh.Hill" ~ "S.Hill",
        passer == "Matt.Moore" | passer == "Mat.Moore" ~ "M.Moore",
        passer == "Jo.Freeman" ~ "J.Freeman",
        passer == "G.Minshew" ~ "G.Minshew II",
        passer == "R.Griffin" ~ "R.Griffin III",
        passer == "Randel El" ~ "A.Randle El",
        passer == "Randle El" ~ "A.Randle El",
        season <= 2003 & passer == "Van Pelt" ~ "A.Van Pelt",
        season > 2003 & passer == "Van Pelt" ~ "B.Van Pelt",
        passer == "Dom.Davis" ~ "D.Davis",
        TRUE ~ .data$passer
      ),
      rusher = dplyr::case_when(
        rusher == "Jos.Allen" ~ "J.Allen",
        rusher == "Alex Smith" | rusher == "Ale.Smith" ~ "A.Smith",
        rusher == "Ryan" & .data$posteam == "ATL" ~ "M.Ryan",
        rusher == "Tr.Brown" ~ "T.Brown",
        rusher == "Sh.Hill" ~ "S.Hill",
        rusher == "Matt.Moore" | rusher == "Mat.Moore" ~ "M.Moore",
        rusher == "Jo.Freeman" ~ "J.Freeman",
        rusher == "G.Minshew" ~ "G.Minshew II",
        rusher == "R.Griffin" ~ "R.Griffin III",
        rusher == "Randel El" ~ "A.Randle El",
        rusher == "Randle El" ~ "A.Randle El",
        season <= 2003 & rusher == "Van Pelt" ~ "A.Van Pelt",
        season > 2003 & rusher == "Van Pelt" ~ "B.Van Pelt",
        rusher == "Dom.Davis" ~ "D.Davis",
        TRUE ~ rusher
      ),
      receiver = dplyr::case_when(
        receiver == "F.R" ~ "F.Jones",
        TRUE ~ receiver
      ),
      first_down = dplyr::if_else(.data$first_down_rush == 1 | .data$first_down_pass == 1 | .data$first_down_penalty == 1, 1, 0),
      aborted_play = dplyr::if_else(stringr::str_detect(.data$desc, 'Aborted'), 1, 0),
      # easy filter: play is 1 if a "special teams" play, or 0 otherwise
      # with thanks to Lee Sharpe for the code
      special = dplyr::if_else(.data$play_type %in%
                       c("extra_point","field_goal","kickoff","punt"), 1, 0),
      # easy filter: play is 1 if a "normal" play (including penalties), or 0 otherwise
      # with thanks to Lee Sharpe for the code
      play = dplyr::if_else(!is.na(.data$epa) & !is.na(.data$posteam) &
                            .data$desc != "*** play under review ***" &
                            substr(.data$desc,1,8) != "Timeout " &
                            .data$play_type %in% c("no_play","pass","run"),1,0)
    ) %>%
    #standardize team names (eg Chargers are always LAC even when they were playing in SD)
    dplyr::mutate_at(dplyr::vars(
      "posteam", "defteam", "home_team", "away_team", "timeout_team", "td_team", "return_team", "penalty_team",
      "side_of_field", "forced_fumble_player_1_team", "forced_fumble_player_2_team",
      "solo_tackle_1_team", "solo_tackle_2_team",
      "assist_tackle_1_team", "assist_tackle_2_team", "assist_tackle_3_team", "assist_tackle_4_team",
      "fumbled_1_team", "fumbled_2_team", "fumble_recovery_1_team", "fumble_recovery_2_team",
      "yrdln", "end_yard_line", "drive_start_yard_line", "drive_end_yard_line"
      ), team_name_fn) %>%

    #Seb's stuff for fixing player ids
    dplyr::mutate(index = 1 : dplyr::n()) %>% # to re-sort after all the group_bys

    dplyr::group_by(.data$passer, .data$posteam, .data$season) %>%
    dplyr::mutate(
      passer_id = dplyr::if_else(is.na(.data$passer), NA_character_, custom_mode(.data$passer_player_id)),
      passer_jersey_number = dplyr::if_else(is.na(.data$passer), NA_integer_, custom_mode(.data$passer_jersey_number))
    ) %>%

    dplyr::group_by(.data$passer_id) %>%
    dplyr::mutate(passer = dplyr::if_else(is.na(.data$passer_id), NA_character_, custom_mode(.data$passer))) %>%

    dplyr::group_by(.data$rusher, .data$posteam, .data$season) %>%
    dplyr::mutate(
      rusher_id = dplyr::if_else(is.na(.data$rusher), NA_character_, custom_mode(.data$rusher_player_id)),
      rusher_jersey_number = dplyr::if_else(is.na(.data$rusher), NA_integer_, custom_mode(.data$rusher_jersey_number))
    ) %>%

    dplyr::group_by(.data$rusher_id) %>%
    dplyr::mutate(rusher = dplyr::if_else(is.na(.data$rusher_id), NA_character_, custom_mode(.data$rusher))) %>%

    dplyr::group_by(.data$receiver, .data$posteam, .data$season) %>%
    dplyr::mutate(
      receiver_id = dplyr::if_else(is.na(.data$receiver), NA_character_, custom_mode(.data$receiver_player_id)),
      receiver_jersey_number = dplyr::if_else(is.na(.data$receiver), NA_integer_, custom_mode(.data$receiver_jersey_number))
    ) %>%

    dplyr::group_by(.data$receiver_id) %>%
    dplyr::mutate(receiver = dplyr::if_else(is.na(.data$receiver_id), NA_character_, custom_mode(.data$receiver))) %>%

    dplyr::ungroup() %>%
    dplyr::mutate(
      name = dplyr::if_else(!is.na(.data$passer), .data$passer, .data$rusher),
      jersey_number = dplyr::if_else(!is.na(.data$passer_jersey_number), .data$passer_jersey_number, .data$rusher_jersey_number),
      id = dplyr::if_else(!is.na(.data$passer_id), .data$passer_id, .data$rusher_id)
    ) %>%
    dplyr::mutate_at(
      dplyr::vars(.data$passer_id, .data$rusher_id, .data$receiver_id, .data$id, ends_with("player_id")),
      update_ids, legacy_id_map) %>%
    dplyr::arrange(.data$index) %>%
    dplyr::select(-"index")

  return(r)
}

#these things are used in clean_pbp() above

# look for First[period or space]Last[maybe - or ' in last][maybe more letters in last][maybe Jr. or II or IV]
big_parser <- "(?<=)[A-Z][A-z]*(\\.|\\s)+[A-Z][A-z]*\\'*\\-*[A-Z]*[a-z]*(\\s((Jr.)|(Sr.)|I{2,3})|(IV))?"
# maybe some spaces and letters, and then a rush direction unless they fumbled
rush_finder <- "(?=\\s*[a-z]*\\s*((FUMBLES) | (left end)|(left tackle)|(left guard)|(up the middle)|(right guard)|(right tackle)|(right end)))"
# maybe some spaces and leters, and then pass / sack / scramble
pass_finder <- "(?=\\s*[a-z]*\\s*(( pass)|(sack)|(scramble)))"
# to or for, maybe a jersey number and a dash
receiver_finder <- "(?<=((to)|(for))\\s[:digit:]{0,2}\\-{0,1})"
# weird play finder
abnormal_play <- "(Lateral)|(lateral)|(pitches to)|(Direct snap to)|(New quarterback for)|(Aborted)|(backwards pass)|(Pass back to)|(Flea-flicker)"
# look for 1-2 numbers before a dash
number_parser <- "((?<=)[:digit:]{1,2}(-))?"
# special case for receivers
receiver_number <- "(?<=((to)|(for))\\s)[:digit:]{0,2}\\-{0,1}"

# These columns are being generated by clean_pbp and the function tries to drop
# them in case it is being used on a pbp dataset where the columns already exist
drop.cols <- c(
  "success", "passer", "rusher", "receiver", "pass", "rush", "special",
  "first_down", "play", "passer_id", "rusher_id", "receiver_id", "name", "id",
  "passer_jersey_number", "rusher_jersey_number", "receiver_jersey_number",
  "jersey_number"
)

# custom mode function from https://stackoverflow.com/questions/2547402/is-there-a-built-in-function-for-finding-the-mode/8189441
custom_mode <- function(x, na.rm = TRUE) {
  if(na.rm){x <- x[!is.na(x)]}
  ux <- unique(x)
  return(ux[which.max(tabulate(match(x, ux)))])
}

# fixes team names on columns with yard line
# example: 'SD 49' --> 'LAC 49'
# thanks to awgymer for the contribution:
# https://github.com/mrcaseb/nflfastR/issues/29#issuecomment-654592195
team_name_fn <- function(var) {
  stringr::str_replace_all(
    var,
    c(
      "JAC" = "JAX",
      "STL" = "LA",
      "SL" = "LA",
      "ARZ" = "ARI",
      "BLT" = "BAL",
      "CLV" = "CLE",
      "HST" = "HOU",
      "SD" = "LAC",
      "OAK" = "LV"
    )
  )
}

#' @importFrom tibble tibble
#' @importFrom rlang .data
#' @importFrom dplyr left_join mutate case_when
update_ids <- function(var, id_map) {
  join <- tibble::tibble(id = var) %>%
    dplyr::left_join(id_map, by = c("id" = "gsis_id")) %>%
    dplyr::mutate(
      out_id = dplyr::case_when(
        is.na(.data$new_id) ~ .data$id,
        TRUE ~ .data$new_id
      )
    )
  return(join$out_id)
}

#' Compute QB epa
#'
#' @param d is a Data frame of play-by-play data scraped using \code{\link{fast_scraper}}.
#' @details Add the variable 'qb_epa', which gives QB credit for EPA for up to the point where
#' a receiver lost a fumble after a completed catch and makes EPA work more
#' like passing yards on plays with fumbles
#' @export
#' @import dplyr
#' @importFrom rlang .data
#' @importFrom tidyselect any_of
add_qb_epa <- function(d) {

  # drop existing values of clean_pbp
  d <- d %>% dplyr::select(-tidyselect::any_of("qb_epa"))

  fumbles_df <- d %>%
    dplyr::filter(.data$complete_pass == 1 & .data$fumble_lost == 1 & !is.na(.data$epa) & !is.na(.data$down)) %>%
    dplyr::mutate(
      half_seconds_remaining = dplyr::if_else(
        .data$half_seconds_remaining <= 6,
        0,
        .data$half_seconds_remaining - 6
      ),
      down = as.numeric(.data$down),
      # save old stuff for testing/checking
      posteam_timeouts_pre = .data$posteam_timeouts_remaining,
      defeam_timeouts_pre = .data$defteam_timeouts_remaining,
      down_old = .data$down,
      ydstogo_old = .data$ydstogo,
      epa_old = .data$epa,
      # update yard line, down, yards to go from play result
      yardline_100 = .data$yardline_100 - .data$yards_gained,
      down = dplyr::if_else(.data$yards_gained >= .data$ydstogo, 1, .data$down + 1),
      # if the fumble spot would have resulted in turnover on downs, need to give other team the ball and fix
      change = dplyr::if_else(.data$down == 5, 1, 0), down = dplyr::if_else(.data$down == 5, 1, .data$down),
      # yards to go is 10 if its a first down, update otherwise
      ydstogo = dplyr::if_else(.data$down == 1, 10, .data$ydstogo - .data$yards_gained),
      # 10 yards to go if possession change
      ydstogo = dplyr::if_else(.data$change == 1, 10, .data$ydstogo),
      # flip field and timeouts for possession change
      yardline_100 = dplyr::if_else(.data$change == 1, 100 - .data$yardline_100, .data$yardline_100),
      posteam_timeouts_remaining = dplyr::if_else(.data$change == 1,
                                                  .data$defeam_timeouts_pre,
                                                  .data$posteam_timeouts_pre),
      defteam_timeouts_remaining = dplyr::if_else(.data$change == 1,
                                                  .data$posteam_timeouts_pre,
                                                  .data$defeam_timeouts_pre),
      # fix yards to go for goal line (eg can't have 1st & 10 inside opponent 10 yard line)
      ydstogo = dplyr::if_else(.data$yardline_100 < .data$ydstogo, .data$yardline_100, .data$ydstogo),
      ep_old = .data$ep
    ) %>%
    dplyr::select(
      "game_id", "play_id",
      "season", "home_team", "posteam", "roof", "half_seconds_remaining",
      "yardline_100", "down", "ydstogo",
      "posteam_timeouts_remaining", "defteam_timeouts_remaining",
      "down_old", "ep_old", "change"
      )

  if (nrow(fumbles_df) > 0) {
    new_ep_df <- calculate_expected_points(fumbles_df) %>%
      dplyr::mutate(ep = dplyr::if_else(.data$change == 1, -.data$ep, .data$ep), fixed_epa = .data$ep - .data$ep_old) %>%
      dplyr::select("game_id", "play_id", "fixed_epa")

    d <- d %>%
      dplyr::left_join(new_ep_df, by = c("game_id", "play_id")) %>%
      dplyr::mutate(qb_epa = dplyr::if_else(!is.na(.data$fixed_epa), .data$fixed_epa, .data$epa)) %>%
      dplyr::select(-"fixed_epa")
  } else {
    d <- d %>% dplyr::mutate(qb_epa = .data$epa)
  }

  return(d)
}

