import 'dart:async';
import 'package:flutter/material.dart';

import 'package:beer_me_up/common/exceptionprint.dart';
import 'package:beer_me_up/common/mvi/viewmodel.dart';
import 'package:beer_me_up/service/userdataservice.dart';
import 'package:beer_me_up/model/beercheckinsdata.dart';
import 'package:beer_me_up/model/beer.dart';
import 'package:beer_me_up/model/checkin.dart';
import 'package:beer_me_up/common/datehelper.dart';
import 'package:beer_me_up/page/checkindisplay/checkindisplaypage.dart';

import 'state.dart';

class ProfileViewModel extends BaseViewModel<ProfileState> {
  final UserDataService _dataService;

  List<BeerCheckInsData> _checkInsData;
  List<CheckIn> _checkIns;
  int _totalPoints;

  StreamSubscription<CheckIn> _checkInSubscription;

  ProfileViewModel(
      this._dataService,
      Stream<Null> onErrorRetryButtonPressed,
      Stream<CheckIn> onRateCheckInPressed) {

    onErrorRetryButtonPressed.listen(_retryLoading);
    onRateCheckInPressed.listen(_rateCheckIn);
  }

  @override
  ProfileState initialState() => ProfileState.loading();

  @override
  Stream<ProfileState> bind(BuildContext context) {
    _loadData();

    return super.bind(context);
  }

  @override
  unbind() {
    _checkInSubscription?.cancel();
    _checkInSubscription = null;

    super.unbind();
  }

  _loadData() async {
    try {
      setState(ProfileState.loading());

      await _loadProfileData();

      _setStateWithProfileData(await _buildProfileData());

      _bindToUpdates();
    } catch (e, stackTrace) {
      printException(e, stackTrace, "Error loading profile");
      setState(ProfileState.error(e.toString()));
    }
  }

  _retryLoading(Null event) async {
    _loadData();
  }

  _loadProfileData() async {
    _checkInsData = List.from(await _dataService.fetchBeerCheckInsData());
    _checkIns = List.from(await _dataService.fetchThisWeekCheckIns());
    _totalPoints = await _dataService.getTotalUserPoints();
  }

  Future<ProfileData> _buildProfileData([CheckIn checkInToRate]) async {
    return ProfileData.fromData(_totalPoints, _checkInsData, _checkIns, checkInToRate);
  }

  void _bindToUpdates() {
    _checkInSubscription?.cancel();
    _checkInSubscription = _dataService.listenForCheckIn().listen((checkIn) {
      _handleCheckIn(checkIn);
    });
  }

  void _handleCheckIn(CheckIn checkIn) async {
    setState(ProfileState.loading());

    try {
      final weekDate = getWeekStartAndEndDate(DateTime.now());
      if( checkIn.date.isAfter(weekDate.item1) && checkIn.date.isBefore(weekDate.item2) ) {
        _checkIns.add(checkIn);
      }

      final int rating = await _dataService.fetchRatingForBeer(checkIn.beer);

      int dataIndex = _checkInsData.indexWhere((checkInData) => checkInData.beer == checkIn.beer);
      if( dataIndex < 0 ) {
        _checkInsData.add(BeerCheckInsData(checkIn.beer, 1, checkIn.date, checkIn.quantity.value, rating));
      } else {
        final currentData = _checkInsData[dataIndex];
        _checkInsData.removeAt(dataIndex);

        _checkInsData.add(BeerCheckInsData(
          checkIn.beer,
          currentData.numberOfCheckIns + 1,
          checkIn.date.isAfter(currentData.lastCheckinTime) ? checkIn.date : currentData.lastCheckinTime,
          currentData.drankQuantity + checkIn.quantity.value,
          rating,
        ));
      }

      _totalPoints += checkIn.points;

      _setStateWithProfileData(await _buildProfileData(rating == null ? checkIn : null));
    } catch (e, stackTrace) {
      printException(e, stackTrace, "Error updating profile");
      setState(ProfileState.error(e.toString()));
    }
  }

  _setStateWithProfileData(ProfileData profileData) {
    if( !profileData.hasAllTime && !profileData.hasWeek ) {
      setState(ProfileState.empty(profileData.hasAlreadyCheckedIn));
    } else if( profileData.hasWeek && profileData.hasAllTime ) {
      setState(ProfileState.load(profileData));
    } else if( profileData.hasAllTime ) {
      setState(ProfileState.loadNoWeek(profileData));
    } else {
      setState(ProfileState.loadNoAllTime(profileData));
    }
  }

  _rateCheckIn(CheckIn checkIn) async {
    pushRoute(
      MaterialPageRoute(
        builder: (BuildContext context) => CheckInDisplayPage(checkIn: checkIn),
      )
    );

    _setStateWithProfileData(await _buildProfileData());
  }
}

class ProfileData {
  final bool hasAllTime;
  final bool hasWeek;
  final bool hasAlreadyCheckedIn;
  final bool hasTopBeers;

  final BeerStyle mostDrankCategory;
  final BeerCheckInsData mostDrankBeer;
  final int totalPoints;

  final List<BeerCheckInsData> weekBeers;
  final int numberOfBeers;
  final int weekPoints;

  final Map<int, List<Beer>> beersRating;
  final CheckIn checkInToRate;

  ProfileData(this.hasAllTime, this.hasWeek, this.hasAlreadyCheckedIn, this.hasTopBeers, this.mostDrankBeer, this.mostDrankCategory, this.weekBeers, this.numberOfBeers, this.weekPoints, this.totalPoints, this.beersRating, this.checkInToRate);

  factory ProfileData.fromData(int totalPoints, List<BeerCheckInsData> checkInsData, List<CheckIn> checkIns, [CheckIn checkInToRate]) {
    final Map<BeerStyle, double> categoriesCounter = Map();

    BeerCheckInsData mostDrankBeer;
    BeerStyle mostDrankCategory;
    double mostDrankCategoryCounter = 0.0;

    int numberOfRatings = 0;
    final Map<int, List<Beer>> beersRating = Map();

    for(BeerCheckInsData checkinData in checkInsData) {
      if( mostDrankBeer == null || checkinData.drankQuantity > mostDrankBeer.drankQuantity ) {
        mostDrankBeer = checkinData;
      }

      final style = checkinData.beer.style;
      if( style != null ) {
        categoriesCounter[style] = categoriesCounter.containsKey(style) ? categoriesCounter[style] + checkinData.drankQuantity : checkinData.drankQuantity;

        final double categoryCount = categoriesCounter[style];
        if( mostDrankCategory == null || categoryCount > mostDrankCategoryCounter ) {
          mostDrankCategory = style;
          mostDrankCategoryCounter = categoryCount;
        }
      }

      if( checkinData.rating != null && numberOfRatings < 10 ) {
        List<Beer> beersForRating = beersRating[checkinData.rating];
        if( beersForRating == null ){
          beersForRating = List();
          beersRating[checkinData.rating] = beersForRating;
        }

        numberOfRatings++;
        beersForRating.add(checkinData.beer);
      }
    }

    final Map<String, BeerCheckInsData> weekBeersMap = Map();
    int points = 0;

    for(CheckIn checkin in checkIns) {
      BeerCheckInsData data = weekBeersMap[checkin.beer.id];

      weekBeersMap[checkin.beer.id] = BeerCheckInsData(
        checkin.beer,
        (data == null ? 0 : data.numberOfCheckIns) + 1,
        data == null ? checkin.date : (data.lastCheckinTime.isBefore(checkin.date) ? checkin.date : data.lastCheckinTime),
        (data == null ? 0.0 : data.drankQuantity) + checkin.quantity.value,
        null,
      );

      points += checkin.points;
    }
    
    final List<BeerCheckInsData> checkInsList = weekBeersMap.values.toList(growable: false);
    checkInsList.sort((a, b) => b.drankQuantity.compareTo(a.drankQuantity));

    final int numberOfCheckIns = checkInsData.isEmpty ? 0 : checkInsData
        .map((checkInData) => checkInData.numberOfCheckIns)
        .reduce((a, b) => a+b);

    return ProfileData(
      numberOfCheckIns >= 2,
      checkIns.length > 0,
      numberOfCheckIns > 0,
      beersRating.isNotEmpty,
      mostDrankBeer,
      mostDrankCategory,
      checkInsList,
      weekBeersMap.length,
      points,
      totalPoints,
      beersRating,
      checkInToRate,
    );
  }
}
