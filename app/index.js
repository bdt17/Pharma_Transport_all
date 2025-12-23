import { View, Text, StyleSheet } from 'react-native';
import { useEffect, useState } from 'react';

export default function HomeScreen() {
  const [sensors, setSensors] = useState([]);

  useEffect(() => {
    fetch('https://pharma-dashboard-s4g5.onrender.com/api/sensors')
      .then(res => res.json())
      .then(setSensors)
      .catch(console.error);
  }, []);

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Pharma Transport 🚚</Text>
      <Text>Live Sensors (2-8°C)</Text>
      {sensors.map(sensor => (
        <Text key={sensor.id}>Truck {sensor.truck_id}: {sensor.temperature}°C</Text>
      ))}
    </View>
  );
}

const styles = StyleSheet.create({
  container: { flex: 1, justifyContent: 'center', alignItems: 'center', backgroundColor: '#f0f8ff', padding: 20 },
  title: { fontSize: 28, fontWeight: 'bold', marginBottom: 30, color: '#1e40af' }
});
