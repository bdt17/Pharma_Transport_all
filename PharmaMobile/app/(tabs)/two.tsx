import React, { useState, useEffect } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import * as Location from 'expo-location';

export default function MapScreen() {
  const [location, setLocation] = useState(null);
  const [error, setError] = useState('');

  useEffect(() => {
    (async () => {
      let { status } = await Location.requestForegroundPermissionsAsync();
      if (status !== 'granted') {
        setError('GPS permission denied');
        return;
      }
      
      let loc = await Location.getCurrentPositionAsync({ accuracy: Location.Accuracy.High });
      setLocation(loc.coords);
    })();
  }, []);

  if (error) {
    return (
      <View style={styles.center}>
        <Text style={styles.error}>{error}</Text>
      </View>
    );
  }

  if (!location) {
    return (
      <View style={styles.center}>
        <Text style={styles.loading}>🚚 Getting GPS location...</Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <View style={styles.mapPlaceholder}>
        <Text style={styles.mapTitle}>🛰️ PHARMA GPS MAP LIVE</Text>
        <Text style={styles.mapStatus}>Phase 11 - Cold Chain Tracking</Text>
      </View>
      
      <View style={styles.coordsCard}>
        <Text style={styles.coordLabel}>📍 CURRENT POSITION</Text>
        <Text style={styles.coordValue}>
          {location.latitude.toFixed(6)}, {location.longitude.toFixed(6)}
        </Text>
        <Text style={styles.altitude}>📏 Alt: {location.altitude?.toFixed(0) || 'N/A'}m</Text>
        <Text style={styles.accuracy}>📡 Accuracy: {location.accuracy?.toFixed(0) || 'N/A'}m</Text>
      </View>

      <View style={styles.statusBar}>
        <Text style={styles.status}>✅ GPS LIVE - Web 13/13 + Mobile</Text>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, backgroundColor: '#f0f9ff' },
  center: { flex: 1, justifyContent: 'center', alignItems: 'center' },
  loading: { fontSize: 20, color: '#1e3a8a' },
  error: { fontSize: 18, color: 'red' },
  mapPlaceholder: { 
    flex: 1, 
    justifyContent: 'center', 
    alignItems: 'center', 
    backgroundColor: '#e0f2fe',
    margin: 20,
    borderRadius: 15
  },
  mapTitle: { fontSize: 24, fontWeight: 'bold', color: '#1e3a8a' },
  mapStatus: { fontSize: 16, color: '#64748b', marginTop: 10 },
  coordsCard: { 
    backgroundColor: 'white', 
    margin: 20, 
    padding: 20, 
    borderRadius: 15, 
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 2 },
    shadowOpacity: 0.1,
    shadowRadius: 4
  },
  coordLabel: { fontSize: 16, color: '#64748b', marginBottom: 10 },
  coordValue: { fontSize: 24, fontWeight: 'bold', color: '#1e3a8a', marginBottom: 10 },
  altitude: { fontSize: 16, color: '#059669' },
  accuracy: { fontSize: 16, color: '#dc2626' },
  statusBar: { 
    backgroundColor: '#10b981', 
    padding: 15, 
    alignItems: 'center' 
  },
  status: { color: 'white', fontWeight: 'bold', fontSize: 16 }
});
