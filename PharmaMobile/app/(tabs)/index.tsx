import { View, Text, StyleSheet } from 'react-native';
import { useState, useEffect } from 'react';

export default function TabOneScreen() {
  const [time, setTime] = useState('');

  useEffect(() => {
    const i = setInterval(() => setTime(new Date().toLocaleTimeString()), 1000);
    return () => clearInterval(i);
  }, []);

  return (
    <View style={styles.c}>
      <Text style={styles.t}>🚚 PHARMA TRANSPORT v10 MOBILE</Text>
      <Text style={styles.s}>Phase 10 LIVE - 6:31 PM MST</Text>
      <Text style={styles.u}>✅ Web 13/13 + iOS/Android</Text>
      <Text style={styles.l}>LIVE: {time}</Text>
      <Text style={styles.f}>GPS | Stripe | DEA | Cold Chain</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  c: {flex:1,alignItems:'center',justifyContent:'center',backgroundColor:'#f0f9ff'},
  t: {fontSize:28,fontWeight:'bold',color:'#1e3a8a',marginBottom:15},
  s: {fontSize:18,color:'#64748b',marginBottom:10},
  u: {fontSize:16,color:'#059669',fontWeight:'600',marginBottom:10},
  l: {fontSize:24,color:'#dc2626',fontWeight:'bold',marginBottom:20},
  f: {fontSize:16,color:'#475569',textAlign:'center'}
});
