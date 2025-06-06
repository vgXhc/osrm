#' @name osrmIsochrone
#' @title Get Polygons of Isochrones
#' @description This function computes areas that are reachable within a
#' given time span from a point and returns the reachable regions as
#' polygons. These areas of equal travel time are called isochrones.
#' @param loc origin point. \code{loc} can be: \itemize{
#'   \item a vector of coordinates (longitude and latitude, WGS 84),
#'   \item a data.frame of longitudes and latitudes (WGS 84),
#'   \item a matrix of longitudes and latitudes (WGS 84),
#'   \item an sfc object of type POINT,
#'   \item an sf object of type POINT.
#' }
#' If \code{loc} is a data.frame, a matrix, an sfc object or an sf object then
#' only the first row or element is considered.
#' @param breaks a numeric vector of break values to define isochrone areas,
#' in minutes.
#' @param exclude pass an optional "exclude" request option to the OSRM API.
#' @param res number of points used to compute isochrones, one side of the square
#' grid, the total number of points will be res*res. Increase res to obtain more
#' detailed isochrones.
#' @param smooth if TRUE a moving window with a gaussian blur is applied to 
#' durations. This option may be usefull to remove small patches of hard to 
#' reach areas. The computed isochrones are less precise but better looking. 
#' @param k size (sigma) of the gaussian moving window. A reasonable value is 
#' used by default.
#' @param osrm.server the base URL of the routing server.
#' getOption("osrm.server") by default.
#' @param osrm.profile the routing profile to use, e.g. "car", "bike" or "foot"
#' (when using the routing.openstreetmap.de test server).
#' getOption("osrm.profile") by default.
#' @return
#' The output of this function is an sf MULTIPOLYGON of isochrones.\cr
#' It contains 3 fields: \itemize{
#'   \item id, an identifier
#'   \item isomin, the minimum value of the isochrone polygon in minutes
#'   \item isomax, the maximum value of the isochrone polygon in minutes
#' }
#' If loc is a vector, a data.frame or a matrix the coordinate
#' reference system (CRS) of the output is EPSG:4326 (WGS84).\cr
#' If loc is an sfc or sf object, the output has the same CRS
#' as loc.\cr
#' @importFrom sf st_as_sf st_crs st_transform st_convex_hull st_union
#' st_intersects st_bbox st_buffer st_distance st_make_grid st_sfc
#' @importFrom mapiso mapiso
#' @export
#' @examples
#' \dontrun{
#' library(sf)
#' apotheke.sf <- st_read(system.file("gpkg/apotheke.gpkg", package = "osrm"),
#'   quiet = TRUE
#' )
#' # Get isochones with lon/lat coordinates
#' iso <- osrmIsochrone(loc = c(13.43, 52.47), breaks = seq(0, 12, 2))
#' # Map
#' plot(iso["isomax"], breaks = sort(unique(c(iso$isomin, iso$isomax))))
#'
#' # Get isochones with an sf POINT
#' iso2 <- osrmIsochrone(loc = apotheke.sf[11, ], breaks = seq(0, 12, 2))
#' # Map
#' if (require("mapsf")) {
#'   mapsf::mf_map(
#'     x = iso2, var = "isomin", type = "choro",
#'     breaks = sort(unique(c(iso2$isomin, iso2$isomax))),
#'     pal = "Burg", border = NA, leg_pos = "topleft",
#'     leg_val_rnd = 0,
#'     leg_frame = TRUE, leg_title = "Isochrones\n(min)"
#'   )
#' }
#' }
osrmIsochrone <- function(loc, breaks = seq(from = 0, to = 60, length.out = 7),
                          exclude, res = 30, smooth = FALSE, k,
                          osrm.server = getOption("osrm.server"),
                          osrm.profile = getOption("osrm.profile")) {
  opt <- options(error = NULL)
  on.exit(options(opt), add = TRUE)

  # input management
  loc <- input_route(x = loc, id = "loc", single = TRUE)
  oprj <- loc$oprj
  loc <- st_as_sf(data.frame(lon = loc$lon, lat = loc$lat),
                  coords = c("lon", "lat"), crs = 4326
  )
  loc <- st_transform(loc, "epsg:3857")
  
  # max distance management to see how far to extend the grid to get measures
  breaks <- unique(sort(breaks))
  tmax <- max(breaks)
  
  # gentle sleeptime & param for demo server
  if (osrm.profile %in% c("foot", "walk")) {
    speed <- 10 * 1000 / 60
  }
  if (osrm.profile == "bike") {
    speed <- 20 * 1000 / 60
  }
  if (osrm.profile %in% c("driving", "car")) {
    speed <- 120 * 1000 / 60
  }
  dmax <- tmax * speed
  
  
  # gentle sleeptime & param for demo server
  if (osrm.server != "https://routing.openstreetmap.de/") {
    sleeptime <- 0
    deco <- 450
  } else {
    sleeptime <- 1
    deco <- 75
  }
  
  # create a grid to obtain measures
  sgrid <- rgrid(loc = loc, dmax = dmax, res = res)
  # slice the grid to make several API calls
  lsgr <- nrow(sgrid)
  niter <- lsgr %/% deco
  nitersup <- lsgr %% deco
  ltot <- niter + ifelse(nitersup > 0, 1, 0)
  listDur <- listDest <- vector(mode = "list", length = ltot)
  # get measures and destinations points
  if (niter > 0) {
    for (i in 1:niter) {
      dmat <- osrmTable(
        src = loc,
        dst = sgrid[(((i - 1) * deco) + 1):(i * deco), ],
        exclude = exclude,
        osrm.server = osrm.server,
        osrm.profile = osrm.profile
      )
      listDur[[i]] <- dmat$durations
      listDest[[i]] <- dmat$destinations
      Sys.sleep(sleeptime)
    }
  }
  if (nitersup > 0) {
    dmat <- osrmTable(
      src = loc,
      dst = sgrid[((niter * deco) + 1):lsgr, ],
      exclude = exclude,
      osrm.server = osrm.server,
      osrm.profile = osrm.profile
    )
    listDur[[ltot]] <- dmat$durations
    listDest[[ltot]] <- dmat$destinations
  }
  
  measure <- do.call(c, listDur)
  destinations <- do.call(rbind, listDest)
  # for testing purpose
  # return(list(destinations = destinations, measure = measure,
  #             sgrid = sgrid, res = res, tmax = tmax))
  
  # assign values to the grid
  sgrid <- fill_grid(
    destinations = destinations, measure = measure,
    sgrid = sgrid, res = res, tmax = tmax
  )
  
  if (min(sgrid$measure, na.rm = TRUE) > tmax) {
    warning(
      paste0(
        "An empty object is returned. ",
        "'loc' is too far from the OSRM network."
      ),
      call. = FALSE
    )
    empty_res <- st_sf(
      crs = ifelse(is.na(oprj), 4326, oprj),
      id = integer(),
      isomin = numeric(),
      isomax = numeric(),
      geometry = st_sfc()
    )
    return(empty_res)
  }
  
  if (isFALSE(smooth)) {
    # All values not within breaks are set to tmax+1 
    sgrid[is.na(sgrid$measure), "measure"] <- tmax + 1
    sgrid[is.nan(sgrid$measure), "measure"] <- tmax + 1
    sgrid[is.infinite(sgrid$measure), "measure"] <- tmax + 1
    sgrid[sgrid$measure > tmax, "measure"] <- tmax + 1
  } else {
    if (!requireNamespace("terra", quietly = TRUE)) {
      stop(paste0(
        "'terra' package is needed for this function to work.",
        "Please install it."
      ), call. = FALSE)
    }
    r <- terra::rast(sgrid[, c("COORDX", "COORDY", "measure"), drop = TRUE], 
              crs = "epsg:3857")
    if (missing(k)) {
      k <- terra::res(r)[1] / 2
    }
    mat <- terra::focalMat(x = r, d = k, type = "Gauss")
    
    # test for invalid focal matrix
    if (sum(dim(mat)) < 6){
      warning(
        paste0(
          "An empty object is returned. ",
          "Select a larger value for 'k'."
        ),
        call. = FALSE
      )
      empty_res <- st_sf(
        crs = ifelse(is.na(oprj), 4326, oprj),
        id = integer(),
        isomin = numeric(),
        isomax = numeric(),
        geometry = st_sfc()
      )
      return(empty_res)
    }
    sgrid <- terra::focal(x = r, w = mat, fun = mean, na.rm = TRUE)
    sgrid[is.na(sgrid)] <- tmax + 1
  }
  
  
  # computes isopolygones
  iso <- mapiso(x = sgrid, breaks = breaks, var = "measure")
  # get rid of out of breaks polys
  iso <- iso[-nrow(iso), ]
  # fisrt line always start at 0
  iso[1, "isomin"] <- 0
  
  # proj mgmnt
  if (!is.na(oprj)) {
    iso <- st_transform(x = iso, oprj)
  } else {
    iso <- st_transform(x = iso, 4326)
  }
  
  return(iso)
}
