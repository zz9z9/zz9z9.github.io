
/* 
   3. Longest Substring Without Repeating Characters
   https://leetcode.com/problems/longest-substring-without-repeating-characters/
*/

class Solution {
    public int lengthOfLongestSubstring(String s) {
        int currentMax = 0;

        for(int i=0; i<s.length(); i++) {
            int maxSubStr = 0;
            Map<Character, Integer> checker = new HashMap<>();

            for(int j=i; j<s.length(); j++) {
                char c = s.charAt(j);

                if(checker.get(c) != null) {
                    break;
                } else {
                    checker.put(c,1);
                    maxSubStr++;
                }
            }
            currentMax = (maxSubStr > currentMax) ? maxSubStr : currentMax;

            if(s.length() - i <= currentMax) {
                break;
            }
        }

        return currentMax;
    }
}
