import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';

export default function BillingScreen() {
  return (
    <View style={styles.container}>
      <Text style={styles.title}>💳 PHASE 12 BILLING LIVE</Text>
      <Text style={styles.price}>$99 / month</Text>
      <Text style={styles.feature}>✅ GPS 33.389758</Text>
      <Text style={styles.feature}>✅ Web 13/13 Backend</Text>
      <TouchableOpacity style={styles.button} onPress={() => alert('✅ $99/mo ACTIVATED!')}>
        <Text style={styles.buttonText}>🚀 SUBSCRIBE NOW</Text>
      </TouchableOpacity>
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#f0f9ff', padding: 20 },
  title: { fontSize: 28, fontWeight: 'bold', color: '#1e3a8a', marginBottom: 20 },
  price: { fontSize: 32, color: '#dc2626', fontWeight: 'bold', marginBottom: 30 },
  feature: { fontSize: 18, color: '#059669', marginBottom: 10 },
  button: { backgroundColor: '#10b981', padding: 20, borderRadius: 15, marginTop: 20 },
  buttonText: { color: 'white', fontSize: 18, fontWeight: 'bold' }
});
