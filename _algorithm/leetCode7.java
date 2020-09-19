// https://leetcode.com/problems/reverse-integer/

class Solution {
    public int reverse(int x) {
        List<Integer> nums = new ArrayList<>();
        boolean negativeFlag = x < 0 ? true : false;
        int mul = negativeFlag ? -1 : 1;
        x = mul*x;
        
        while(x > 0){
            int remainder = x%10;
            nums.add(remainder);
            
            x = x/10;
        }
        
        String reversedNum = "0";
        
        for(int i=0; i<nums.size(); i++) {  
           reversedNum = reversedNum + Integer.toString(nums.get(i));
        }
        
        int result;
        
        try {
            result = mul * Integer.parseInt(reversedNum);
        } catch (Exception e) { // overFlow 
            result = 0;
        }   
         
        return result;
    }
}
